// src/lib.rs
use anyhow::{Context, Result};
use aws_sdk_s3::Client as S3Client;
use bitcoin::secp256k1::{rand, PublicKey, Secp256k1, SecretKey};
use bitcoin::{Address, Network, PrivateKey};
use rayon::prelude::*;
use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use tracing::{error, info, warn};

#[derive(Debug, Clone)]
pub struct FoundAddress {
    pub address: String,
    pub private_key_wif: String,
    pub address_type: String,
}

pub struct BitcoinMatcher {
    pub target_addresses: Arc<HashSet<String>>,
    pub network: Network,
    pub counter: Arc<AtomicU64>,
    pub found_counter: Arc<AtomicU64>,
}

impl BitcoinMatcher {
    pub fn new(target_addresses: HashSet<String>, network: Network) -> Self {
        Self {
            target_addresses: Arc::new(target_addresses),
            network,
            counter: Arc::new(AtomicU64::new(0)),
            found_counter: Arc::new(AtomicU64::new(0)),
        }
    }

    pub fn generate_and_check_batch(&self, batch_size: usize) -> Vec<FoundAddress> {
        let secp = Secp256k1::new();
        let mut found = Vec::new();
        let mut rng = rand::thread_rng();

        for _ in 0..batch_size {
            // Generate random private key
            let private_key = SecretKey::new(&mut rng);
            let bitcoin_private_key = PrivateKey::new(private_key, self.network);
            
            // Generate public key
            let public_key = PublicKey::from_secret_key(&secp, &private_key);
            
            // Generate different address types
            let addresses = self.generate_addresses(&public_key, &bitcoin_private_key);
            
            // Check against target list
            for (addr_type, address, wif) in addresses {
                if self.target_addresses.contains(&address) {
                    found.push(FoundAddress {
                        address: address.clone(),
                        private_key_wif: wif,
                        address_type: addr_type,
                    });
                    self.found_counter.fetch_add(1, Ordering::Relaxed);
                    info!("🎉 MATCH FOUND! Address: {}, Type: {}", address, addr_type);
                }
            }
            
            self.counter.fetch_add(1, Ordering::Relaxed);
        }

        found
    }

    pub fn generate_addresses(&self, public_key: &PublicKey, private_key: &PrivateKey) -> Vec<(String, String, String)> {
        let mut addresses = Vec::new();
        let wif = private_key.to_wif();

        // P2PKH (Legacy) - starts with 1
        if let Ok(addr) = Address::p2pkh(public_key, self.network) {
            addresses.push(("P2PKH".to_string(), addr.to_string(), wif.clone()));
        }

        // P2SH-P2WPKH (Nested SegWit) - starts with 3
        if let Ok(addr) = Address::p2shwpkh(public_key, self.network) {
            addresses.push(("P2SH-P2WPKH".to_string(), addr.to_string(), wif.clone()));
        }

        // P2WPKH (Native SegWit) - starts with bc1
        if let Ok(addr) = Address::p2wpkh(public_key, self.network) {
            addresses.push(("P2WPKH".to_string(), addr.to_string(), wif.clone()));
        }

        addresses
    }

    pub fn get_stats(&self) -> (u64, u64) {
        (
            self.counter.load(Ordering::Relaxed),
            self.found_counter.load(Ordering::Relaxed),
        )
    }
}

pub async fn load_target_addresses(s3_client: &S3Client, bucket: &str, key: &str) -> Result<HashSet<String>> {
    info!("Loading target addresses from s3://{}/{}", bucket, key);
    
    let response = s3_client
        .get_object()
        .bucket(bucket)
        .key(key)
        .send()
        .await
        .context("Failed to download addresses file from S3")?;

    let body = response.body.collect().await?;
    let content = String::from_utf8(body.into_bytes().to_vec())?;
    
    let addresses: HashSet<String> = content
        .lines()
        .map(|line| line.trim().to_string())
        .filter(|line| !line.is_empty())
        .collect();

    info!("Loaded {} target addresses", addresses.len());
    Ok(addresses)
}

pub fn parse_network(network_str: &str) -> Result<Network> {
    match network_str.to_lowercase().as_str() {
        "mainnet" => Ok(Network::Bitcoin),
        "testnet" => Ok(Network::Testnet),
        "signet" => Ok(Network::Signet),
        "regtest" => Ok(Network::Regtest),
        _ => Err(anyhow::anyhow!("Invalid network: {}", network_str)),
    }
}

pub async fn save_found_addresses(found_addresses: &[FoundAddress]) -> Result<()> {
    if found_addresses.is_empty() {
        return Ok(());
    }

    let timestamp = chrono::Utc::now().format("%Y%m%d_%H%M%S");
    let filename = format!("found_addresses_{}.txt", timestamp);
    
    let mut content = String::new();
    content.push_str("# Found Bitcoin Addresses\n");
    content.push_str(&format!("# Generated at: {}\n", chrono::Utc::now()));
    content.push_str("# Format: Address,PrivateKey(WIF),AddressType\n\n");
    
    for found in found_addresses {
        content.push_str(&format!(
            "{},{},{}\n",
            found.address, found.private_key_wif, found.address_type
        ));
    }

    tokio::fs::write(&filename, content).await?;
    info!("Saved {} found addresses to {}", found_addresses.len(), filename);
    Ok(())
}