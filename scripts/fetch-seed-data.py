#!/usr/bin/env python3
"""
MCP Registry Seed Data Fetcher

This script fetches the official MCP registry seed data from GitHub
and creates a sample subset for Kubernetes ConfigMap deployment.

The full seed.json file is too large for a single Kubernetes ConfigMap
(~492KB becomes >1MB when base64 encoded), so we create a representative
sample for demonstration purposes.
"""

import json
import urllib.request
import sys
import os
from pathlib import Path

# GitHub raw URL for the official seed data
SEED_DATA_URL = "https://raw.githubusercontent.com/modelcontextprotocol/registry/main/data/seed.json"

def fetch_seed_data(url: str) -> list:
    """Fetch seed data from GitHub repository."""
    print(f"Fetching seed data from: {url}")
    
    try:
        with urllib.request.urlopen(url) as response:
            if response.status != 200:
                raise Exception(f"HTTP {response.status}: {response.reason}")
            
            data = json.loads(response.read().decode('utf-8'))
            print(f"Successfully fetched {len(data)} MCP servers")
            return data
            
    except Exception as e:
        print(f"Error fetching seed data: {e}")
        raise

def create_sample_data(full_data: list, sample_size: int = 10) -> list:
    """Create a representative sample of the seed data."""
    
    # Take a diverse sample from different parts of the data
    total_servers = len(full_data)
    
    if total_servers <= sample_size:
        return full_data
    
    # Take servers from different positions to get variety
    step = total_servers // sample_size
    sample_indices = [i * step for i in range(sample_size)]
    
    sample = [full_data[i] for i in sample_indices]
    
    # Update server names to use anonymous namespace for our deployment
    for server in sample:
        original_name = server['name']
        # Convert to anonymous namespace while preserving the original pattern
        namespace_part = original_name.split('/', 1)[-1] if '/' in original_name else original_name
        server['name'] = f"io.modelcontextprotocol.anonymous/{namespace_part}"
        
        # Add a note about the conversion
        server['description'] = f"[DEMO] {server.get('description', 'No description')}"
        
        # Ensure we have a version
        if 'version' not in server or not server['version']:
            server['version'] = '1.0.0'
    
    return sample

def save_sample_data(sample_data: list, output_file: str):
    """Save the sample data to a JSON file."""
    
    # Ensure output directory exists
    output_path = Path(output_file)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    
    with open(output_file, 'w') as f:
        json.dump(sample_data, f, indent=2)
    
    print(f"Saved {len(sample_data)} sample servers to: {output_file}")

def validate_sample_data(sample_file: str):
    """Validate the created sample data."""
    try:
        with open(sample_file, 'r') as f:
            data = json.load(f)
        
        # Basic validation
        if not isinstance(data, list):
            raise ValueError("Data should be a list")
        
        if len(data) == 0:
            raise ValueError("No servers in sample data")
        
        # Validate each server has required fields
        for i, server in enumerate(data):
            required_fields = ['name', 'description', 'version']
            for field in required_fields:
                if field not in server:
                    raise ValueError(f"Server {i} missing required field: {field}")
        
        print(f"✓ Sample data validation passed: {len(data)} servers")
        return True
        
    except Exception as e:
        print(f"✗ Sample data validation failed: {e}")
        return False

def main():
    """Main function to fetch and process seed data."""
    
    # Command line arguments
    if len(sys.argv) > 1:
        output_file = sys.argv[1]
    else:
        # Default output location
        script_dir = Path(__file__).parent
        output_file = script_dir.parent / "deploy" / "sample-seed.json"
    
    # Optional sample size argument
    sample_size = 10
    if len(sys.argv) > 2:
        try:
            sample_size = int(sys.argv[2])
        except ValueError:
            print(f"Invalid sample size: {sys.argv[2]}, using default: {sample_size}")
    
    try:
        print("🚀 MCP Registry Seed Data Fetcher")
        print("=" * 50)
        
        # Fetch full seed data from GitHub
        full_data = fetch_seed_data(SEED_DATA_URL)
        
        # Create sample data suitable for ConfigMap
        sample_data = create_sample_data(full_data, sample_size)
        
        # Save sample data
        save_sample_data(sample_data, str(output_file))
        
        # Validate the created sample
        if validate_sample_data(str(output_file)):
            print("\n✅ Success! Sample seed data ready for deployment")
            print(f"📁 Output file: {output_file}")
            print(f"📊 Sample size: {len(sample_data)} servers (from {len(full_data)} total)")
            print(f"💾 File size: {os.path.getsize(output_file)} bytes")
            
            # Show some example server names
            print("\n📋 Sample servers included:")
            for i, server in enumerate(sample_data[:5]):
                print(f"  {i+1}. {server['name']}")
            if len(sample_data) > 5:
                print(f"  ... and {len(sample_data) - 5} more")
                
        else:
            sys.exit(1)
            
    except Exception as e:
        print(f"❌ Error: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()