use anyhow::{Context, Result};
use aws_config::BehaviorVersion;
use aws_sdk_s3::Client as S3Client;
use bitcoin::secp256k1::{rand, PublicKey, Secp256k1, SecretKey};
use bitcoin::{Address, Network, PrivateKey};
use clap::Parser;
use rayon::prelude::*;
use std::collections::HashSet;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Arc;
use std::time::{Duration, Instant};
use tracing::{error, info, warn};

#[derive(Parser, Debug)]
#[command(author, version, about, long_about = None)]
struct Args {
    /// S3 bucket name containing target addresses
    #[arg(short, long, env = "BUCKET_NAME")]
    bucket: String,

    /// S3 object key for the addresses file
    #[arg(short, long, default_value = "bitcoin_addresses.txt")]
    key: String,

    /// Number of worker threads
    #[arg(short, long, default_value_t = num_cpus::get())]
    threads: usize,

    /// Number of addresses to generate per batch
    #[arg(long, default_value_t = 1000)]
    batch_size: usize,

    /// Bitcoin network (mainnet, testnet, signet, regtest)
    #[arg(short, long, default_value = "mainnet")]
    network: String,

    /// Progress reporting interval (seconds)
    #[arg(long, default_value_t = 10)]
    report_interval: u64,
}

struct BitcoinMatcher {
    target_addresses: Arc<HashSet<String>>,
    network: Network,
    counter: Arc<AtomicU64>,
    found_counter: Arc<AtomicU64>,
}

impl BitcoinMatcher {
    fn new(target_addresses: HashSet<String>, network: Network) -> Self {
        Self {
            target_addresses: Arc::new(target_addresses),
            network,
            counter: Arc::new(AtomicU64::new(0)),
            found_counter: Arc::new(AtomicU64::new(0)),
        }
    }

    fn generate_and_check_batch(&self, batch_size: usize) -> Vec<FoundAddress> {
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

    fn generate_addresses(&self, public_key: &PublicKey, private_key: &PrivateKey) -> Vec<(String, String, String)> {
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

    fn get_stats(&self) -> (u64, u64) {
        (
            self.counter.load(Ordering::Relaxed),
            self.found_counter.load(Ordering::Relaxed),
        )
    }
}

#[derive(Debug, Clone)]
struct FoundAddress {
    address: String,
    private_key_wif: String,
    address_type: String,
}

async fn load_target_addresses(s3_client: &S3Client, bucket: &str, key: &str) -> Result<HashSet<String>> {
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

fn parse_network(network_str: &str) -> Result<Network> {
    match network_str.to_lowercase().as_str() {
        "mainnet" => Ok(Network::Bitcoin),
        "testnet" => Ok(Network::Testnet),
        "signet" => Ok(Network::Signet),
        "regtest" => Ok(Network::Regtest),
        _ => Err(anyhow::anyhow!("Invalid network: {}", network_str)),
    }
}

async fn save_found_addresses(found_addresses: &[FoundAddress]) -> Result<()> {
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

#[tokio::main]
async fn main() -> Result<()> {
    tracing_subscriber::fmt::init();
    
    let args = Args::parse();
    
    // Validate network
    let network = parse_network(&args.network)?;
    info!("Using Bitcoin network: {:?}", network);

    // Set up thread pool
    rayon::ThreadPoolBuilder::new()
        .num_threads(args.threads)
        .build_global()?;

    // Initialize AWS S3 client
    let config = aws_config::defaults(BehaviorVersion::latest()).load().await;
    let s3_client = S3Client::new(&config);

    // Load target addresses from S3
    let target_addresses = load_target_addresses(&s3_client, &args.bucket, &args.key).await?;
    
    if target_addresses.is_empty() {
        warn!("No target addresses loaded. Exiting.");
        return Ok(());
    }

    // Initialize matcher
    let matcher = Arc::new(BitcoinMatcher::new(target_addresses, network));
    let mut found_addresses = Vec::new();

    // Progress reporting
    let report_matcher = matcher.clone();
    let report_interval = Duration::from_secs(args.report_interval);
    let start_time = Instant::now();
    
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(report_interval);
        loop {
            interval.tick().await;
            let (total, found) = report_matcher.get_stats();
            let elapsed = start_time.elapsed().as_secs();
            let rate = if elapsed > 0 { total / elapsed } else { 0 };
            
            info!(
                "Progress: {} addresses generated, {} matches found, {} addr/sec",
                total, found, rate
            );
        }
    });

    info!("Starting Bitcoin address generation with {} threads", args.threads);
    info!("Batch size: {}", args.batch_size);

    // Main generation loop
    loop {
        let batch_results: Vec<Vec<FoundAddress>> = (0..args.threads)
            .into_par_iter()
            .map(|_| {
                let matcher_clone = matcher.clone();
                matcher_clone.generate_and_check_batch(args.batch_size)
            })
            .collect();

        // Collect results
        for batch in batch_results {
            found_addresses.extend(batch);
        }

        // Save found addresses periodically
        if !found_addresses.is_empty() {
            save_found_addresses(&found_addresses).await?;
            found_addresses.clear();
        }

        // Small delay to prevent overwhelming the system
        tokio::time::sleep(Duration::from_millis(10)).await;
    }
}

// Add to Cargo.toml dependencies:
// num_cpus = "1.16"
// chrono = { version = "0.4", features = ["serde"] }