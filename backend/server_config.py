"""Server configuration management with port fallback."""

import socket
import json
import os
from typing import Optional, List

class ServerConfig:
    """Manages server configuration including port fallback."""
    
    DEFAULT_PORTS = [8000, 8001, 8002, 8003, 8004, 8080, 3000, 5000]
    CONFIG_FILE = "server_config.json"
    
    def __init__(self):
        self.host = "127.0.0.1"
        self.port = None
        self.available_ports = []
        self.config = self.load_config()
    
    def load_config(self) -> dict:
        """Load configuration from file."""
        if os.path.exists(self.CONFIG_FILE):
            try:
                with open(self.CONFIG_FILE, 'r') as f:
                    return json.load(f)
            except Exception as e:
                print(f"⚠️ Error loading config: {e}")
        return {"last_used_port": None}
    
    def save_config(self):
        """Save configuration to file."""
        try:
            with open(self.CONFIG_FILE, 'w') as f:
                json.dump(self.config, f, indent=2)
        except Exception as e:
            print(f"⚠️ Error saving config: {e}")
    
    def is_port_available(self, port: int, host: str = "127.0.0.1") -> bool:
        """Check if a port is available."""
        try:
            with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
                sock.settimeout(1)
                result = sock.connect_ex((host, port))
                return result != 0  # Port is available if connection fails
        except Exception:
            return False
    
    def find_available_port(self, preferred_port: Optional[int] = None) -> int:
        """Find an available port, preferring the specified port."""
        ports_to_try = []
        
        # Try preferred port first
        if preferred_port:
            ports_to_try.append(preferred_port)
        
        # Try last used port
        if self.config.get("last_used_port"):
            ports_to_try.append(self.config["last_used_port"])
        
        # Try default ports
        ports_to_try.extend(self.DEFAULT_PORTS)
        
        # Remove duplicates while preserving order
        seen = set()
        unique_ports = []
        for port in ports_to_try:
            if port not in seen:
                seen.add(port)
                unique_ports.append(port)
        
        for port in unique_ports:
            if self.is_port_available(port, self.host):
                self.port = port
                self.config["last_used_port"] = port
                self.save_config()
                print(f"✅ Found available port: {port}")
                return port
        
        raise RuntimeError("❌ No available ports found")
    
    def get_server_url(self) -> str:
        """Get the full server URL."""
        if not self.port:
            raise RuntimeError("Port not configured")
        return f"http://{self.host}:{self.port}"
    
    def scan_available_ports(self) -> List[int]:
        """Scan for all available ports."""
        available = []
        for port in self.DEFAULT_PORTS:
            if self.is_port_available(port, self.host):
                available.append(port)
        self.available_ports = available
        return available

# Global server config instance
server_config = ServerConfig()