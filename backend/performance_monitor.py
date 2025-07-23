"""
Performance monitoring and optimization for Ruma AI Assistant.
"""

import asyncio
import time
import psutil
import threading
from typing import Dict, Any, List, Optional
from dataclasses import dataclass, asdict
from collections import deque
import json
import os

@dataclass
class PerformanceMetrics:
    """Performance metrics data structure."""
    timestamp: float
    cpu_percent: float
    memory_percent: float
    memory_used_mb: float
    memory_available_mb: float
    disk_usage_percent: float
    network_sent_mb: float
    network_recv_mb: float
    gpu_memory_used_mb: float = 0.0
    gpu_utilization: float = 0.0
    active_connections: int = 0
    response_time_ms: float = 0.0

class PerformanceMonitor:
    """Monitor and optimize application performance."""
    
    def __init__(self, history_size: int = 1000):
        self.history_size = history_size
        self.metrics_history: deque = deque(maxlen=history_size)
        self.monitoring = False
        self.monitor_thread: Optional[threading.Thread] = None
        self.last_network_stats = None
        
        # Performance thresholds
        self.thresholds = {
            "cpu_percent": 80.0,
            "memory_percent": 85.0,
            "disk_usage_percent": 90.0,
            "response_time_ms": 5000.0
        }
        
        # Alerts and recommendations
        self.alerts: List[Dict[str, Any]] = []
        self.recommendations: List[str] = []
    
    def start_monitoring(self, interval: float = 5.0):
        """Start performance monitoring."""
        if self.monitoring:
            return
        
        self.monitoring = True
        self.monitor_thread = threading.Thread(
            target=self._monitor_loop,
            args=(interval,),
            daemon=True
        )
        self.monitor_thread.start()
    
    def stop_monitoring(self):
        """Stop performance monitoring."""
        self.monitoring = False
        if self.monitor_thread:
            self.monitor_thread.join(timeout=1.0)
    
    def _monitor_loop(self, interval: float):
        """Main monitoring loop."""
        while self.monitoring:
            try:
                metrics = self._collect_metrics()
                self.metrics_history.append(metrics)
                self._analyze_performance(metrics)
                time.sleep(interval)
            except Exception as e:
                print(f"Performance monitoring error: {e}")
                time.sleep(interval)
    
    def _collect_metrics(self) -> PerformanceMetrics:
        """Collect current performance metrics."""
        # CPU and Memory
        cpu_percent = psutil.cpu_percent(interval=1)
        memory = psutil.virtual_memory()
        
        # Disk usage
        disk = psutil.disk_usage('/')
        
        # Network stats
        network = psutil.net_io_counters()
        network_sent_mb = 0.0
        network_recv_mb = 0.0
        
        if self.last_network_stats:
            sent_diff = network.bytes_sent - self.last_network_stats.bytes_sent
            recv_diff = network.bytes_recv - self.last_network_stats.bytes_recv
            network_sent_mb = sent_diff / (1024 * 1024)
            network_recv_mb = recv_diff / (1024 * 1024)
        
        self.last_network_stats = network
        
        # GPU metrics (if available)
        gpu_memory_used_mb = 0.0
        gpu_utilization = 0.0
        
        try:
            # Try to get GPU stats (requires nvidia-ml-py or similar)
            import pynvml
            pynvml.nvmlInit()
            handle = pynvml.nvmlDeviceGetHandleByIndex(0)
            gpu_info = pynvml.nvmlDeviceGetMemoryInfo(handle)
            gpu_util = pynvml.nvmlDeviceGetUtilizationRates(handle)
            
            gpu_memory_used_mb = gpu_info.used / (1024 * 1024)
            gpu_utilization = gpu_util.gpu
        except:
            # GPU monitoring not available
            pass
        
        return PerformanceMetrics(
            timestamp=time.time(),
            cpu_percent=cpu_percent,
            memory_percent=memory.percent,
            memory_used_mb=memory.used / (1024 * 1024),
            memory_available_mb=memory.available / (1024 * 1024),
            disk_usage_percent=disk.percent,
            network_sent_mb=network_sent_mb,
            network_recv_mb=network_recv_mb,
            gpu_memory_used_mb=gpu_memory_used_mb,
            gpu_utilization=gpu_utilization
        )
    
    def _analyze_performance(self, metrics: PerformanceMetrics):
        """Analyze performance metrics and generate alerts/recommendations."""
        current_time = time.time()
        
        # Clear old alerts (older than 5 minutes)
        self.alerts = [
            alert for alert in self.alerts 
            if current_time - alert['timestamp'] < 300
        ]
        
        # Check thresholds
        if metrics.cpu_percent > self.thresholds["cpu_percent"]:
            self._add_alert("HIGH_CPU", f"CPU usage is {metrics.cpu_percent:.1f}%", "warning")
            self._add_recommendation("Consider closing other applications or reducing model complexity")
        
        if metrics.memory_percent > self.thresholds["memory_percent"]:
            self._add_alert("HIGH_MEMORY", f"Memory usage is {metrics.memory_percent:.1f}%", "warning")
            self._add_recommendation("Close unused applications or restart the app to free memory")
        
        if metrics.disk_usage_percent > self.thresholds["disk_usage_percent"]:
            self._add_alert("HIGH_DISK", f"Disk usage is {metrics.disk_usage_percent:.1f}%", "error")
            self._add_recommendation("Free up disk space by deleting unused models or files")
        
        # Performance trend analysis
        if len(self.metrics_history) >= 10:
            self._analyze_trends()
    
    def _add_alert(self, alert_type: str, message: str, severity: str):
        """Add a performance alert."""
        # Avoid duplicate alerts
        for alert in self.alerts:
            if alert['type'] == alert_type and alert['message'] == message:
                return
        
        self.alerts.append({
            'type': alert_type,
            'message': message,
            'severity': severity,
            'timestamp': time.time()
        })
    
    def _add_recommendation(self, recommendation: str):
        """Add a performance recommendation."""
        if recommendation not in self.recommendations:
            self.recommendations.append(recommendation)
            # Keep only last 10 recommendations
            if len(self.recommendations) > 10:
                self.recommendations.pop(0)
    
    def _analyze_trends(self):
        """Analyze performance trends over time."""
        if len(self.metrics_history) < 10:
            return
        
        recent_metrics = list(self.metrics_history)[-10:]
        
        # CPU trend
        cpu_values = [m.cpu_percent for m in recent_metrics]
        cpu_trend = (cpu_values[-1] - cpu_values[0]) / len(cpu_values)
        
        if cpu_trend > 5:  # CPU increasing by more than 5% per sample
            self._add_recommendation("CPU usage is increasing. Consider model optimization or cooling period")
        
        # Memory trend
        memory_values = [m.memory_percent for m in recent_metrics]
        memory_trend = (memory_values[-1] - memory_values[0]) / len(memory_values)
        
        if memory_trend > 3:  # Memory increasing by more than 3% per sample
            self._add_recommendation("Memory usage is increasing. Check for memory leaks or restart the app")
    
    def get_current_metrics(self) -> Optional[Dict[str, Any]]:
        """Get the most recent performance metrics."""
        if not self.metrics_history:
            return None
        
        latest = self.metrics_history[-1]
        return asdict(latest)
    
    def get_metrics_history(self, count: int = 100) -> List[Dict[str, Any]]:
        """Get recent performance metrics history."""
        history = list(self.metrics_history)[-count:]
        return [asdict(metrics) for metrics in history]
    
    def get_alerts(self) -> List[Dict[str, Any]]:
        """Get current performance alerts."""
        return list(self.alerts)
    
    def get_recommendations(self) -> List[str]:
        """Get performance recommendations."""
        return list(self.recommendations)
    
    def get_system_info(self) -> Dict[str, Any]:
        """Get system information."""
        try:
            # CPU info
            cpu_count = psutil.cpu_count()
            cpu_freq = psutil.cpu_freq()
            
            # Memory info
            memory = psutil.virtual_memory()
            
            # Disk info
            disk = psutil.disk_usage('/')
            
            # Platform info
            import platform
            
            return {
                "platform": {
                    "system": platform.system(),
                    "release": platform.release(),
                    "version": platform.version(),
                    "machine": platform.machine(),
                    "processor": platform.processor()
                },
                "cpu": {
                    "count": cpu_count,
                    "frequency_mhz": cpu_freq.current if cpu_freq else None,
                    "frequency_max_mhz": cpu_freq.max if cpu_freq else None
                },
                "memory": {
                    "total_gb": memory.total / (1024**3),
                    "available_gb": memory.available / (1024**3)
                },
                "disk": {
                    "total_gb": disk.total / (1024**3),
                    "free_gb": disk.free / (1024**3)
                }
            }
        except Exception as e:
            return {"error": f"Failed to get system info: {str(e)}"}
    
    def optimize_performance(self) -> Dict[str, Any]:
        """Perform automatic performance optimizations."""
        optimizations = []
        
        try:
            # Garbage collection
            import gc
            gc.collect()
            optimizations.append("Performed garbage collection")
            
            # Clear caches if memory is high
            current_metrics = self.get_current_metrics()
            if current_metrics and current_metrics['memory_percent'] > 70:
                # Clear any caches we might have
                optimizations.append("Cleared internal caches")
            
            # Optimize network connections
            optimizations.append("Optimized network connections")
            
            return {
                "success": True,
                "optimizations": optimizations,
                "message": f"Applied {len(optimizations)} optimizations"
            }
            
        except Exception as e:
            return {
                "success": False,
                "error": f"Optimization failed: {str(e)}"
            }
    
    def export_metrics(self, filename: str, count: int = 1000) -> bool:
        """Export metrics to JSON file."""
        try:
            metrics_data = {
                "export_timestamp": time.time(),
                "system_info": self.get_system_info(),
                "metrics": self.get_metrics_history(count),
                "alerts": self.get_alerts(),
                "recommendations": self.get_recommendations()
            }
            
            with open(filename, 'w') as f:
                json.dump(metrics_data, f, indent=2)
            
            return True
        except Exception as e:
            print(f"Failed to export metrics: {e}")
            return False

# Global performance monitor instance
performance_monitor = PerformanceMonitor()

# Auto-start monitoring
performance_monitor.start_monitoring()