// benches/address_generation.rs
use criterion::{black_box, criterion_group, criterion_main, Criterion, BenchmarkId};
use bitcoin_matcher::{BitcoinMatcher, parse_network};
use bitcoin::{Network, PrivateKey};
use std::collections::HashSet;

fn benchmark_single_address_generation(c: &mut Criterion) {
    let target_addresses = HashSet::new();
    let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
    
    c.bench_function("single_address_generation", |b| {
        b.iter(|| {
            black_box(matcher.generate_and_check_batch(1));
        });
    });
}

fn benchmark_batch_address_generation(c: &mut Criterion) {
    let target_addresses = HashSet::new();
    let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
    
    let mut group = c.benchmark_group("batch_address_generation");
    
    for batch_size in [10, 100, 1000, 5000].iter() {
        group.bench_with_input(
            BenchmarkId::new("batch_size", batch_size),
            batch_size,
            |b, &batch_size| {
                b.iter(|| {
                    black_box(matcher.generate_and_check_batch(batch_size));
                });
            },
        );
    }
    group.finish();
}

fn benchmark_address_type_generation(c: &mut Criterion) {
    let target_addresses = HashSet::new();
    let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
    
    // Use a known private key for consistent benchmarking
    let private_key = PrivateKey::from_wif("L4rK1yDtCWekvXuE6oXD9jCYfFNV2cWRpVuPLBcCU2z8TrisoyY1").unwrap();
    let secp = bitcoin::secp256k1::Secp256k1::new();
    let public_key = private_key.public_key(&secp);
    
    c.bench_function("address_type_generation", |b| {
        b.iter(|| {
            black_box(matcher.generate_addresses(&public_key, &private_key));
        });
    });
}

fn benchmark_network_parsing(c: &mut Criterion) {
    let networks = ["mainnet", "testnet", "signet", "regtest"];
    
    c.bench_function("network_parsing", |b| {
        b.iter(|| {
            for network in &networks {
                black_box(parse_network(network).unwrap());
            }
        });
    });
}

fn benchmark_target_matching(c: &mut Criterion) {
    // Create various sized target sets
    let mut group = c.benchmark_group("target_matching");
    
    for target_count in [10, 100, 1000, 10000].iter() {
        let target_addresses: HashSet<String> = (0..*target_count)
            .map(|i| format!("1Address{:010}", i))
            .collect();
        
        let matcher = BitcoinMatcher::new(target_addresses, Network::Bitcoin);
        
        group.bench_with_input(
            BenchmarkId::new("target_count", target_count),
            target_count,
            |b, _| {
                b.iter(|| {
                    black_box(matcher.generate_and_check_batch(100));
                });
            },
        );
    }
    group.finish();
}

fn benchmark_parallel_generation(c: &mut Criterion) {
    use rayon::prelude::*;
    use std::sync::Arc;
    
    let target_addresses = HashSet::