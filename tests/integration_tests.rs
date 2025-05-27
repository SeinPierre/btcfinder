// tests/integration_tests.rs
use bitcoin::{Network, PrivateKey};
use bitcoin_matcher::{BitcoinMatcher, FoundAddress, parse_network};
use std::collections::HashSet;
use tokio;

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_parse_network() {
        assert_eq!(parse_network("mainnet").unwrap(), Network::Bitcoin);
        assert_eq!(parse_network("MAINNET").unwrap(), Network::Bitcoin);
        assert_eq!(parse_network("testnet").unwrap(), Network::Testnet);
        assert_eq!(parse_network("signet").unwrap(), Network::Signet);
        assert_eq!(parse_network("regtest").unwrap(), Network::Regtest);
        
        assert!(parse_network("invalid").is_err());
        assert!(parse_network("").is_err());
    }

    #[test]
    fn test_bitcoin_matcher_creation() {
        let target_addresses = HashSet::from([
            "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa".to_string(),
            "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy".to_string(),
        ]);
        
        let matcher = BitcoinMatcher::new(target_addresses.clone(), Network::Bitcoin);
        let (counter, found_counter) = matcher.get_stats();
        
        assert_eq!(counter, 0);
        assert_eq!(found_counter, 0);
        assert_eq!(matcher.target_addresses.len(), 2);
    }

    #[test]
    fn test_address_generation() {
        let target_addresses = HashSet::new();
        let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
        
        // Generate a known private key for testing
        let private_key = PrivateKey::from_wif("L4rK1yDtCWekvXuE6oXD9jCYfFNV2cWRpVuPLBcCU2z8TrisoyY1").unwrap();
        let public_key = private_key.public_key(&bitcoin::secp256k1::Secp256k1::new());
        
        let addresses = matcher.generate_addresses(&public_key, &private_key);
        
        // Should generate at least 3 address types
        assert!(addresses.len() >= 3);
        
        // Check that we have different address types
        let types: HashSet<String> = addresses.iter().map(|(t, _, _)| t.clone()).collect();
        assert!(types.contains("P2PKH"));
        assert!(types.contains("P2WPKH"));
        
        // Verify all addresses have the same WIF
        let wif = &addresses[0].2;
        for (_, _, addr_wif) in &addresses {
            assert_eq!(addr_wif, wif);
        }
    }

    #[test]
    fn test_batch_generation_no_matches() {
        let target_addresses = HashSet::from([
            "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa".to_string(), // Genesis block address (very unlikely to generate)
        ]);
        
        let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
        let found = matcher.generate_and_check_batch(10);
        
        // Very unlikely to find a match with only 10 generations
        assert_eq!(found.len(), 0);
        
        let (counter, found_counter) = matcher.get_stats();
        assert_eq!(counter, 10);
        assert_eq!(found_counter, 0);
    }

    #[test]
    fn test_batch_generation_with_known_match() {
        // Create a known address from a known private key
        let private_key = PrivateKey::from_wif("L4rK1yDtCWekvXuE6oXD9jCYfFNV2cWRpVuPLBcCU2z8TrisoyY1").unwrap();
        let public_key = private_key.public_key(&bitcoin::secp256k1::Secp256k1::new());
        
        // Generate the P2PKH address for this key
        let address = bitcoin::Address::p2pkh(&public_key, Network::Bitcoin).unwrap();
        
        let target_addresses = HashSet::from([address.to_string()]);
        let matcher = BitcoinMatcherTestable::new(target_addresses, Network::Bitcoin);
        
        // Use our test method that uses the known private key
        let found = matcher.generate_and_check_batch_with_key(1, private_key);
        
        assert_eq!(found.len(), 1);
        assert_eq!(found[0].address, address.to_string());
        assert_eq!(found[0].address_type, "P2PKH");
    }

    #[tokio::test]
    async fn test_save_found_addresses() {
        let found_addresses = vec![
            FoundAddress {
                address: "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa".to_string(),
                private_key_wif: "L4rK1yDtCWekvXuE6oXD9jCYfFNV2cWRpVuPLBcCU2z8TrisoyY1".to_string(),
                address_type: "P2PKH".to_string(),
            },
            FoundAddress {
                address: "3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy".to_string(),
                private_key_wif: "L1aW4aubDFB7yfras2S1mN3bqg9nwySY8nkoLmJebSLD5BWv3ENZ".to_string(),
                address_type: "P2SH-P2WPKH".to_string(),
            },
        ];

        let result = bitcoin_matcher::save_found_addresses(&found_addresses).await;
        assert!(result.is_ok());

        // Clean up - remove the test file
        let timestamp = chrono::Utc::now().format("%Y%m%d");
        let pattern = format!("found_addresses_{}", timestamp);
        
        if let Ok(entries) = std::fs::read_dir(".") {
            for entry in entries.flatten() {
                if let Some(name) = entry.file_name().to_str() {
                    if name.starts_with(&pattern) {
                        let _ = std::fs::remove_file(entry.path());
                    }
                }
            }
        }
    }

    #[test]
    fn test_empty_target_addresses() {
        let target_addresses = HashSet::new();
        let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
        
        let found = matcher.generate_and_check_batch(5);
        assert_eq!(found.len(), 0);
        
        let (counter, found_counter) = matcher.get_stats();
        assert_eq!(counter, 5);
        assert_eq!(found_counter, 0);
    }

    #[test]
    fn test_different_networks() {
        let target_addresses = HashSet::from([
            "tb1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh".to_string(), // Testnet address
        ]);
        
        let matcher_mainnet = BitcoinMatcher::new(target_addresses.clone(), Network::Bitcoin);
        let matcher_testnet = BitcoinMatcher::new(target_addresses, Network::Testnet);
        
        // Generate with same private key on different networks
        let private_key = PrivateKey::from_wif("cTpB4YiyKiBcPxnefsDpbnDxFDffjqJob8wGCEDXxgQ7zQoMXJdH").unwrap();
        let public_key = private_key.public_key(&bitcoin::secp256k1::Secp256k1::new());
        
        let mainnet_addresses = matcher_mainnet.generate_addresses(&public_key, &private_key);
        let testnet_addresses = matcher_testnet.generate_addresses(&public_key, &private_key);
        
        // Addresses should be different for different networks
        assert_ne!(mainnet_addresses[0].1, testnet_addresses[0].1);
    }

    #[test]
    fn test_stats_thread_safety() {
        use std::sync::Arc;
        use std::thread;
        
        let target_addresses = HashSet::new();
        let matcher = Arc::new(BitcoinMatcher::new(target_addresses, Network::Bitcoin));
        
        let mut handles = vec![];
        
        // Spawn multiple threads to test thread safety
        for _ in 0..4 {
            let matcher_clone = matcher.clone();
            let handle = thread::spawn(move || {
                matcher_clone.generate_and_check_batch(10);
            });
            handles.push(handle);
        }
        
        // Wait for all threads to complete
        for handle in handles {
            handle.join().unwrap();
        }
        
        let (counter, found_counter) = matcher.get_stats();
        assert_eq!(counter, 40); // 4 threads * 10 addresses each
        assert_eq!(found_counter, 0);
    }
}

// Test helper struct that allows injecting known private keys
pub struct BitcoinMatcherTestable {
    matcher: BitcoinMatcher,
}

impl BitcoinMatcherTestable {
    pub fn new(target_addresses: HashSet<String>, network: Network) -> Self {
        Self {
            matcher: BitcoinMatcher::new(target_addresses, network),
        }
    }
    
    pub fn generate_and_check_batch_with_key(&self, batch_size: usize, private_key: PrivateKey) -> Vec<FoundAddress> {
        let secp = bitcoin::secp256k1::Secp256k1::new();
        let mut found = Vec::new();
        
        for _ in 0..batch_size {
            let public_key = private_key.public_key(&secp);
            let addresses = self.matcher.generate_addresses(&public_key, &private_key);
            
            for (addr_type, address, wif) in addresses {
                if self.matcher.target_addresses.contains(&address) {
                    found.push(FoundAddress {
                        address: address.clone(),
                        private_key_wif: wif,
                        address_type: addr_type,
                    });
                    self.matcher.found_counter.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
                }
            }
            
            self.matcher.counter.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
        }
        
        found
    }
}

// Benchmark tests (requires 'cargo bench')
#[cfg(test)]
mod benchmarks {
    use super::*;
    use std::time::Instant;

    #[test]
    fn benchmark_address_generation() {
        let target_addresses = HashSet::new();
        let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
        
        let start = Instant::now();
        let iterations = 1000;
        
        for _ in 0..iterations {
            matcher.generate_and_check_batch(1);
        }
        
        let duration = start.elapsed();
        let rate = iterations as f64 / duration.as_secs_f64();
        
        println!("Generated {:.2} addresses/sec", rate);
        assert!(rate > 100.0); // Should generate at least 100 addresses per second
    }

    #[test]
    fn benchmark_batch_generation() {
        let target_addresses = HashSet::new();
        let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
        
        let start = Instant::now();
        let batch_size = 1000;
        
        matcher.generate_and_check_batch(batch_size);
        
        let duration = start.elapsed();
        let rate = batch_size as f64 / duration.as_secs_f64();
        
        println!("Batch generated {:.2} addresses/sec", rate);
        assert!(rate > 500.0); // Batch should be more efficient
    }
}

// Property-based tests (requires 'proptest' crate)
#[cfg(test)]
mod property_tests {
    use super::*;
    use proptest::prelude::*;

    proptest! {
        #[test]
        fn test_address_generation_always_produces_valid_addresses(
            seed in any::<u64>()
        ) {
            use bitcoin::secp256k1::{rand::SeedableRng, rand::rngs::StdRng};
            
            let target_addresses = HashSet::new();
            let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
            
            let mut rng = StdRng::seed_from_u64(seed);
            let secp = bitcoin::secp256k1::Secp256k1::new();
            let private_key_bytes = bitcoin::secp256k1::SecretKey::new(&mut rng);
            let private_key = PrivateKey::new(private_key_bytes, Network::Bitcoin);
            let public_key = private_key.public_key(&secp);
            
            let addresses = matcher.generate_addresses(&public_key, &private_key);
            
            // Should always generate at least one address
            prop_assert!(!addresses.is_empty());
            
            // All addresses should be valid Bitcoin addresses
            for (addr_type, address, _) in addresses {
                prop_assert!(!addr_type.is_empty());
                prop_assert!(!address.is_empty());
                prop_assert!(address.len() > 25); // Bitcoin addresses are at least 26 chars
                
                // Verify address can be parsed
                let parsed = bitcoin::Address::from_str(&address);
                prop_assert!(parsed.is_ok(), "Invalid address generated: {}", address);
            }
        }

        #[test]
        fn test_stats_consistency(
            batch_sizes in prop::collection::vec(1usize..100, 1..10)
        ) {
            let target_addresses = HashSet::new();
            let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
            
            let mut expected_total = 0;
            
            for batch_size in batch_sizes {
                matcher.generate_and_check_batch(batch_size);
                expected_total += batch_size;
            }
            
            let (actual_total, found_count) = matcher.get_stats();
            prop_assert_eq!(actual_total as usize, expected_total);
            prop_assert_eq!(found_count, 0); // No matches expected with empty target
        }
    }
}

// Mock tests for S3 integration
#[cfg(test)]
mod s3_tests {
    use super::*;
    use std::collections::HashMap;

    // Mock S3 client for testing
    pub struct MockS3Client {
        pub objects: HashMap<String, String>,
    }

    impl MockS3Client {
        pub fn new() -> Self {
            Self {
                objects: HashMap::new(),
            }
        }
        
        pub fn put_object(&mut self, key: String, content: String) {
            self.objects.insert(key, content);
        }
        
        pub fn get_object(&self, key: &str) -> Option<&String> {
            self.objects.get(key)
        }
    }

    #[test]
    fn test_mock_s3_operations() {
        let mut mock_s3 = MockS3Client::new();
        
        // Test data
        let addresses = "1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa\n3J98t1WpEZ73CNmQviecrnyiWrnqRhWNLy\nbc1qxy2kgdygjrsqtzq2n0yrf2493p83kkfjhx0wlh";
        
        // Put object
        mock_s3.put_object("bitcoin_addresses.txt".to_string(), addresses.to_string());
        
        // Get object
        let retrieved = mock_s3.get_object("bitcoin_addresses.txt").unwrap();
        assert_eq!(retrieved, addresses);
        
        // Parse addresses
        let parsed_addresses: HashSet<String> = retrieved
            .lines()
            .map(|line| line.trim().to_string())
            .filter(|line| !line.is_empty())
            .collect();
        
        assert_eq!(parsed_addresses.len(), 3);
        assert!(parsed_addresses.contains("1A1zP1eP5QGefi2DMPTfTL5SLmv7DivfNa"));
    }
}

// Error handling tests
#[cfg(test)]
mod error_tests {
    use super::*;

    #[test]
    fn test_invalid_private_key() {
        let result = PrivateKey::from_wif("invalid_wif");
        assert!(result.is_err());
    }

    #[test]
    fn test_invalid_network_string() {
        let result = parse_network("invalid_network");
        assert!(result.is_err());
        
        let error_msg = format!("{}", result.unwrap_err());
        assert!(error_msg.contains("Invalid network"));
    }

    #[tokio::test]
    async fn test_save_empty_addresses() {
        let empty_addresses = vec![];
        let result = bitcoin_matcher::save_found_addresses(&empty_addresses).await;
        assert!(result.is_ok());
    }
}