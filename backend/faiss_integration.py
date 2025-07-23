"""
FAISS Integration for Production Vector Storage
==============================================

Implements FAISS IVF-PQ and HNSW indices for optimal performance and compression.
"""

import numpy as np
import faiss
import pickle
import os
from typing import List, Tuple, Optional, Dict, Any
from pathlib import Path
import time

class FAISSManager:
    """
    Manages FAISS indices for different performance requirements
    """
    
    def __init__(self, embedding_dim: int = 1536, base_path: str = "./faiss_indices"):
        self.embedding_dim = embedding_dim
        self.base_path = Path(base_path)
        self.base_path.mkdir(exist_ok=True)
        
        # Configuration for different tiers
        self.config = {
            "hot": {
                "type": "HNSW",
                "M": 32,
                "efConstruction": 200,
                "efSearch": 50,
                "max_elements": 10000
            },
            "warm": {
                "type": "IVF_PQ",
                "nlist": 100,
                "m": 8,
                "nbits": 8,
                "max_elements": 100000
            },
            "cold": {
                "type": "PQ",
                "m": 16,
                "nbits": 8,
                "max_elements": 1000000
            }
        }
        
        # Initialize indices
        self.indices = {}
        self.id_maps = {}  # Map FAISS IDs to original IDs
        
        self._init_indices()
        
    def _init_indices(self):
        """Initialize FAISS indices for each tier"""
        for tier, config in self.config.items():
            index_path = self.base_path / f"{tier}_index.faiss"
            id_map_path = self.base_path / f"{tier}_id_map.pkl"
            
            if index_path.exists():
                # Load existing index
                self.indices[tier] = faiss.read_index(str(index_path))
                
                # Load ID mapping
                if id_map_path.exists():
                    with open(id_map_path, 'rb') as f:
                        self.id_maps[tier] = pickle.load(f)
                else:
                    self.id_maps[tier] = {}
            else:
                # Create new index
                self.indices[tier] = self._create_index(tier, config)
                self.id_maps[tier] = {}
            
            print(f"✅ {tier.upper()} index initialized: {self.indices[tier].ntotal} vectors")
    
    def _create_index(self, tier: str, config: Dict[str, Any]) -> faiss.Index:
        """Create a new FAISS index based on configuration"""
        d = self.embedding_dim
        
        if config["type"] == "HNSW":
            # HNSW for hot tier (fastest search)
            index = faiss.IndexHNSWFlat(d, config["M"])
            index.hnsw.efConstruction = config["efConstruction"]
            index.hnsw.efSearch = config["efSearch"]
            
        elif config["type"] == "IVF_PQ":
            # IVF-PQ for warm tier (balanced performance/compression)
            quantizer = faiss.IndexFlatL2(d)
            index = faiss.IndexIVFPQ(
                quantizer, d, 
                config["nlist"], 
                config["m"], 
                config["nbits"]
            )
            
        elif config["type"] == "PQ":
            # Pure PQ for cold tier (maximum compression)
            index = faiss.IndexPQ(d, config["m"], config["nbits"])
            
        else:
            raise ValueError(f"Unknown index type: {config['type']}")
        
        print(f"🆕 Created new {config['type']} index for {tier} tier")
        return index
    
    def add_vectors(self, tier: str, vectors: np.ndarray, ids: List[str]) -> List[int]:
        """
        Add vectors to specified tier index
        Returns FAISS internal IDs
        """
        if tier not in self.indices:
            raise ValueError(f"Unknown tier: {tier}")
        
        # Convert to float16 for storage efficiency
        vectors_f16 = vectors.astype(np.float16)
        
        # Get current index size (starting FAISS ID)
        start_id = self.indices[tier].ntotal
        
        # Train index if needed (for IVF indices)
        if hasattr(self.indices[tier], 'is_trained') and not self.indices[tier].is_trained:
            if vectors_f16.shape[0] >= self.config[tier]["nlist"]:
                print(f"🎯 Training {tier} index with {vectors_f16.shape[0]} vectors...")
                self.indices[tier].train(vectors_f16)
            else:
                print(f"⚠️ Not enough vectors to train {tier} index (need {self.config[tier]['nlist']})")
        
        # Add vectors to index
        try:
            self.indices[tier].add(vectors_f16)
            
            # Update ID mapping
            faiss_ids = list(range(start_id, start_id + len(ids)))
            for faiss_id, original_id in zip(faiss_ids, ids):
                self.id_maps[tier][faiss_id] = original_id
            
            print(f"➕ Added {len(ids)} vectors to {tier} tier (total: {self.indices[tier].ntotal})")
            
            # Save periodically
            if self.indices[tier].ntotal % 1000 == 0:
                self.save_index(tier)
            
            return faiss_ids
            
        except Exception as e:
            print(f"❌ Failed to add vectors to {tier}: {e}")
            return []
    
    def search(self, tier: str, query_vector: np.ndarray, k: int = 10) -> Tuple[List[float], List[str]]:
        """
        Search for similar vectors in specified tier
        Returns (distances, original_ids)
        """
        if tier not in self.indices:
            return [], []
        
        try:
            # Convert query to float16
            query_f16 = query_vector.astype(np.float16).reshape(1, -1)
            
            # Perform search
            distances, faiss_ids = self.indices[tier].search(query_f16, k)
            
            # Convert FAISS IDs back to original IDs
            original_ids = []
            valid_distances = []
            
            for dist, faiss_id in zip(distances[0], faiss_ids[0]):
                if faiss_id != -1 and faiss_id in self.id_maps[tier]:
                    original_ids.append(self.id_maps[tier][faiss_id])
                    valid_distances.append(float(dist))
            
            return valid_distances, original_ids
            
        except Exception as e:
            print(f"❌ Search failed in {tier}: {e}")
            return [], []
    
    def multi_tier_search(self, query_vector: np.ndarray, k: int = 10, tiers: List[str] = None) -> List[Dict[str, Any]]:
        """
        Search across multiple tiers and merge results
        """
        if tiers is None:
            tiers = ["hot", "warm", "cold"]
        
        all_results = []
        
        for tier in tiers:
            if tier in self.indices and self.indices[tier].ntotal > 0:
                distances, ids = self.search(tier, query_vector, k)
                
                for dist, original_id in zip(distances, ids):
                    all_results.append({
                        "id": original_id,
                        "distance": dist,
                        "tier": tier
                    })
        
        # Sort by distance and return top k
        all_results.sort(key=lambda x: x["distance"])
        return all_results[:k]
    
    def remove_vectors(self, tier: str, ids: List[str]) -> int:
        """
        Remove vectors by original IDs (mark as deleted)
        Note: FAISS doesn't support true deletion, so we remove from ID mapping
        """
        if tier not in self.id_maps:
            return 0
        
        removed_count = 0
        faiss_ids_to_remove = []
        
        # Find FAISS IDs for original IDs
        for faiss_id, original_id in list(self.id_maps[tier].items()):
            if original_id in ids:
                faiss_ids_to_remove.append(faiss_id)
                del self.id_maps[tier][faiss_id]
                removed_count += 1
        
        print(f"🗑️ Marked {removed_count} vectors as deleted in {tier} tier")
        return removed_count
    
    def get_index_stats(self, tier: str) -> Dict[str, Any]:
        """Get statistics for specified index"""
        if tier not in self.indices:
            return {}
        
        index = self.indices[tier]
        config = self.config[tier]
        
        # Calculate storage size
        index_path = self.base_path / f"{tier}_index.faiss"
        file_size_mb = index_path.stat().st_size / (1024 * 1024) if index_path.exists() else 0
        
        stats = {
            "type": config["type"],
            "total_vectors": index.ntotal,
            "dimension": self.embedding_dim,
            "file_size_mb": file_size_mb,
            "active_ids": len(self.id_maps[tier]),
            "is_trained": getattr(index, 'is_trained', True),
            "compression_ratio": self._estimate_compression_ratio(tier)
        }
        
        # Add tier-specific stats
        if config["type"] == "HNSW":
            stats.update({
                "M": config["M"],
                "efSearch": index.hnsw.efSearch
            })
        elif config["type"] == "IVF_PQ":
            stats.update({
                "nlist": config["nlist"],
                "m": config["m"],
                "nbits": config["nbits"]
            })
        elif config["type"] == "PQ":
            stats.update({
                "m": config["m"],
                "nbits": config["nbits"]
            })
        
        return stats
    
    def _estimate_compression_ratio(self, tier: str) -> float:
        """Estimate compression ratio for the index"""
        config = self.config[tier]
        
        if config["type"] == "HNSW":
            # HNSW stores full vectors (float16 = 2 bytes per dim)
            return 2.0  # float32 -> float16
        
        elif config["type"] == "IVF_PQ":
            # PQ compression: m subvectors, nbits per code
            bytes_per_vector = config["m"] * (config["nbits"] / 8)
            original_bytes = self.embedding_dim * 4  # float32
            return original_bytes / bytes_per_vector
        
        elif config["type"] == "PQ":
            # Pure PQ compression
            bytes_per_vector = config["m"] * (config["nbits"] / 8)
            original_bytes = self.embedding_dim * 4  # float32
            return original_bytes / bytes_per_vector
        
        return 1.0
    
    def save_index(self, tier: str):
        """Save index and ID mapping to disk"""
        if tier not in self.indices:
            return
        
        try:
            # Save FAISS index
            index_path = self.base_path / f"{tier}_index.faiss"
            faiss.write_index(self.indices[tier], str(index_path))
            
            # Save ID mapping
            id_map_path = self.base_path / f"{tier}_id_map.pkl"
            with open(id_map_path, 'wb') as f:
                pickle.dump(self.id_maps[tier], f)
            
            print(f"💾 Saved {tier} index and ID mapping")
            
        except Exception as e:
            print(f"❌ Failed to save {tier} index: {e}")
    
    def save_all_indices(self):
        """Save all indices and mappings"""
        for tier in self.indices.keys():
            self.save_index(tier)
    
    def optimize_all(self) -> Dict[str, Any]:
        """
        Perform comprehensive optimization of all indices
        """
        start_time = time.time()
        results = {
            "started_at": time.time(),
            "operations": [],
            "stats_before": {},
            "stats_after": {},
            "execution_time_ms": 0
        }
        
        # Get stats before optimization
        for tier in self.indices.keys():
            results["stats_before"][tier] = self.get_index_stats(tier)
        
        # Optimize each tier
        for tier in self.indices.keys():
            try:
                if self.config[tier]["type"] == "IVF_PQ":
                    # Retrain if we have enough data
                    if self.indices[tier].ntotal > self.config[tier]["nlist"] * 10:
                        # Get sample for training
                        sample_size = min(10000, self.indices[tier].ntotal)
                        training_data = self.indices[tier].reconstruct_n(0, sample_size)
                        self.indices[tier].train(training_data)
                        results["operations"].append(f"Retrained {tier} IVF index")
                
                # Save optimized index
                self.save_index(tier)
                results["operations"].append(f"Saved {tier} index")
                
            except Exception as e:
                results["operations"].append(f"Failed to optimize {tier}: {e}")
        
        # Get stats after optimization
        for tier in self.indices.keys():
            results["stats_after"][tier] = self.get_index_stats(tier)
        
        results["execution_time_ms"] = (time.time() - start_time) * 1000
        
        print(f"🔧 FAISS optimization completed in {results['execution_time_ms']:.0f}ms")
        print(f"   Operations: {len(results['operations'])}")
        
        return results
    
    def get_memory_usage(self) -> Dict[str, float]:
        """Get memory usage statistics for all indices"""
        usage = {}
        
        for tier in self.indices.keys():
            index_path = self.base_path / f"{tier}_index.faiss"
            id_map_path = self.base_path / f"{tier}_id_map.pkl"
            
            index_size = index_path.stat().st_size if index_path.exists() else 0
            id_map_size = id_map_path.stat().st_size if id_map_path.exists() else 0
            
            usage[tier] = {
                "index_mb": index_size / (1024 * 1024),
                "id_map_mb": id_map_size / (1024 * 1024),
                "total_mb": (index_size + id_map_size) / (1024 * 1024),
                "vectors": self.indices[tier].ntotal,
                "mb_per_1k_vectors": ((index_size + id_map_size) / (1024 * 1024)) / max(1, self.indices[tier].ntotal / 1000)
            }
        
        return usage

# Global instance
faiss_manager = None

def get_faiss_manager() -> FAISSManager:
    """Get or create global FAISS manager"""
    global faiss_manager
    if faiss_manager is None:
        faiss_manager = FAISSManager()
    return faiss_manager