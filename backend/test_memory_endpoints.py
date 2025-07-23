#!/usr/bin/env python3
"""
Test script for memory management endpoints
"""

import requests
import json
import time

BASE_URL = "http://127.0.0.1:8000"
USER_ID = "pradhumn"

def test_endpoint(endpoint, method="GET", data=None, description=""):
    """Test a single endpoint"""
    print(f"\n🧪 Testing {method} {endpoint}")
    print(f"📝 {description}")
    
    try:
        if method == "GET":
            response = requests.get(f"{BASE_URL}{endpoint}")
        elif method == "POST":
            response = requests.post(f"{BASE_URL}{endpoint}", json=data)
        elif method == "DELETE":
            response = requests.delete(f"{BASE_URL}{endpoint}")
        
        print(f"Status: {response.status_code}")
        
        if response.status_code == 200:
            result = response.json()
            if result.get("success"):
                print("✅ SUCCESS")
                if "message" in result:
                    print(f"Message: {result['message']}")
                return result
            else:
                print("❌ FAILED")
                print(f"Error: {result.get('error', 'Unknown error')}")
        else:
            print("❌ HTTP ERROR")
            print(f"Response: {response.text[:200]}")
    
    except Exception as e:
        print(f"❌ EXCEPTION: {e}")
    
    return None

def main():
    print("🔧 Testing Memory Management Endpoints")
    print("=" * 50)
    
    # Test 1: List memories with pagination
    test_endpoint(
        f"/memory/list/{USER_ID}?limit=10&offset=0",
        "GET",
        description="List memories with pagination"
    )
    
    # Test 2: Memory statistics
    test_endpoint(
        f"/memory/stats/{USER_ID}",
        "GET", 
        description="Get memory statistics"
    )
    
    # Test 3: Optimize memory
    test_endpoint(
        f"/memory/optimize/{USER_ID}?force=true",
        "POST",
        description="Force optimize memory with vector database support"
    )
    
    # Test 4: Store a test memory (for deletion test)
    test_memory = {
        "user_id": USER_ID,
        "content": "Test memory for deletion test",
        "memory_type": "test",
        "importance": 0.5
    }
    
    result = test_endpoint(
        "/memory/store",
        "POST",
        data=test_memory,
        description="Store a test memory"
    )
    
    # Test 5: Delete the test memory
    if result and "memory_id" in result:
        memory_id = result["memory_id"]
        test_endpoint(
            f"/memory/delete/{memory_id}",
            "DELETE",
            description="Delete single memory from both databases"
        )
    
    # Test 6: DANGEROUS - Clear all memories (commented out for safety)
    # print("\n⚠️ Skipping clear all memories test for safety")
    # test_endpoint(
    #     f"/memory/clear_all_memories/{USER_ID}",
    #     "DELETE",
    #     description="Clear all memories from both databases"
    # )
    
    print("\n✅ Testing completed!")

if __name__ == "__main__":
    main()