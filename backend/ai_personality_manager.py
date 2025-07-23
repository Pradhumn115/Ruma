"""
AI Assistant Personality Manager
Allows users to create, customize, and switch between different AI assistant personalities.
"""

import asyncio
import json
import sqlite3
import uuid
from typing import Dict, List, Any, Optional
from datetime import datetime
from dataclasses import dataclass, asdict
from enum import Enum

class PersonalityTrait(Enum):
    FRIENDLY = "friendly"
    PROFESSIONAL = "professional"
    CREATIVE = "creative"
    ANALYTICAL = "analytical"
    SUPPORTIVE = "supportive"
    HUMOROUS = "humorous"
    DIRECT = "direct"
    EMPATHETIC = "empathetic"
    ENERGETIC = "energetic"
    CALM = "calm"

class CommunicationStyle(Enum):
    CASUAL = "casual"
    FORMAL = "formal"
    TECHNICAL = "technical"
    CONVERSATIONAL = "conversational"
    CONCISE = "concise"
    DETAILED = "detailed"

class ExpertiseDomain(Enum):
    GENERAL = "general"
    TECHNOLOGY = "technology"
    BUSINESS = "business"
    CREATIVE = "creative"
    SCIENCE = "science"
    EDUCATION = "education"
    HEALTH = "health"
    ENTERTAINMENT = "entertainment"

@dataclass
class AIPersonality:
    id: str
    user_id: str
    name: str
    description: str
    personality_traits: List[str]
    communication_style: str
    expertise_domains: List[str]
    response_length: str  # brief, medium, detailed
    formality_level: float  # 0-1
    creativity_level: float  # 0-1
    empathy_level: float  # 0-1
    humor_level: float  # 0-1
    custom_instructions: str
    avatar_icon: str
    color_theme: str
    is_active: bool
    created_at: datetime
    updated_at: datetime
    usage_count: int

class AIPersonalityManager:
    """Manages AI assistant personalities for users."""
    
    def __init__(self, db_path: str = "./ai_personalities.db"):
        self.db_path = db_path
        self.setup_database()
    
    def setup_database(self):
        """Initialize the personalities database."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # AI Personalities table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS ai_personalities (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                name TEXT NOT NULL,
                description TEXT,
                personality_traits TEXT, -- JSON array
                communication_style TEXT,
                expertise_domains TEXT, -- JSON array
                response_length TEXT DEFAULT 'medium',
                formality_level REAL DEFAULT 0.5,
                creativity_level REAL DEFAULT 0.5,
                empathy_level REAL DEFAULT 0.5,
                humor_level REAL DEFAULT 0.3,
                custom_instructions TEXT,
                avatar_icon TEXT DEFAULT '🤖',
                color_theme TEXT DEFAULT 'blue',
                is_active BOOLEAN DEFAULT FALSE,
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                usage_count INTEGER DEFAULT 0,
                UNIQUE(user_id, name)
            )
        ''')
        
        # Personality Usage History
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS personality_usage (
                id TEXT PRIMARY KEY,
                user_id TEXT NOT NULL,
                personality_id TEXT NOT NULL,
                session_id TEXT,
                messages_count INTEGER DEFAULT 0,
                session_duration INTEGER DEFAULT 0,
                satisfaction_rating INTEGER, -- 1-5
                used_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                FOREIGN KEY (personality_id) REFERENCES ai_personalities (id)
            )
        ''')
        
        conn.commit()
        conn.close()
    
    async def create_personality(self, user_id: str, personality_data: Dict[str, Any]) -> AIPersonality:
        """Create a new AI personality for a user."""
        
        personality_id = str(uuid.uuid4())
        now = datetime.now()
        
        # Create personality object
        personality = AIPersonality(
            id=personality_id,
            user_id=user_id,
            name=personality_data.get("name", "Assistant"),
            description=personality_data.get("description", "A helpful AI assistant"),
            personality_traits=personality_data.get("personality_traits", ["friendly", "helpful"]),
            communication_style=personality_data.get("communication_style", "conversational"),
            expertise_domains=personality_data.get("expertise_domains", ["general"]),
            response_length=personality_data.get("response_length", "medium"),
            formality_level=personality_data.get("formality_level", 0.5),
            creativity_level=personality_data.get("creativity_level", 0.5),
            empathy_level=personality_data.get("empathy_level", 0.5),
            humor_level=personality_data.get("humor_level", 0.3),
            custom_instructions=personality_data.get("custom_instructions", ""),
            avatar_icon=personality_data.get("avatar_icon", "🤖"),
            color_theme=personality_data.get("color_theme", "blue"),
            is_active=personality_data.get("is_active", False),
            created_at=now,
            updated_at=now,
            usage_count=0
        )
        
        # Store in database
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            INSERT INTO ai_personalities (
                id, user_id, name, description, personality_traits, communication_style,
                expertise_domains, response_length, formality_level, creativity_level,
                empathy_level, humor_level, custom_instructions, avatar_icon,
                color_theme, is_active, created_at, updated_at, usage_count
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ''', (
            personality.id, personality.user_id, personality.name, personality.description,
            json.dumps(personality.personality_traits), personality.communication_style,
            json.dumps(personality.expertise_domains), personality.response_length,
            personality.formality_level, personality.creativity_level,
            personality.empathy_level, personality.humor_level,
            personality.custom_instructions, personality.avatar_icon,
            personality.color_theme, personality.is_active,
            personality.created_at.isoformat(), personality.updated_at.isoformat(),
            personality.usage_count
        ))
        
        conn.commit()
        conn.close()
        
        print(f"✅ Created AI personality '{personality.name}' for user {user_id}")
        return personality
    
    async def get_user_personalities(self, user_id: str) -> List[AIPersonality]:
        """Get all personalities for a user."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT * FROM ai_personalities 
            WHERE user_id = ? 
            ORDER BY is_active DESC, usage_count DESC, created_at DESC
        ''', (user_id,))
        
        rows = cursor.fetchall()
        conn.close()
        
        personalities = []
        for row in rows:
            personality = AIPersonality(
                id=row[0],
                user_id=row[1],
                name=row[2],
                description=row[3],
                personality_traits=json.loads(row[4]),
                communication_style=row[5],
                expertise_domains=json.loads(row[6]),
                response_length=row[7],
                formality_level=row[8],
                creativity_level=row[9],
                empathy_level=row[10],
                humor_level=row[11],
                custom_instructions=row[12],
                avatar_icon=row[13],
                color_theme=row[14],
                is_active=bool(row[15]),
                created_at=datetime.fromisoformat(row[16]),
                updated_at=datetime.fromisoformat(row[17]),
                usage_count=row[18]
            )
            personalities.append(personality)
        
        return personalities
    
    async def get_active_personality(self, user_id: str) -> Optional[AIPersonality]:
        """Get the currently active personality for a user."""
        personalities = await self.get_user_personalities(user_id)
        
        for personality in personalities:
            if personality.is_active:
                return personality
        
        # If no active personality, return the most used one or create default
        if personalities:
            return personalities[0]
        else:
            # Create a default personality
            default_data = {
                "name": "Alex",
                "description": "A friendly and helpful AI assistant",
                "personality_traits": ["friendly", "supportive", "analytical"],
                "communication_style": "conversational",
                "expertise_domains": ["general"],
                "avatar_icon": "🤖",
                "is_active": True
            }
            return await self.create_personality(user_id, default_data)
    
    async def switch_personality(self, user_id: str, personality_id: str) -> bool:
        """Switch to a different personality."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Deactivate all personalities for this user
        cursor.execute('''
            UPDATE ai_personalities 
            SET is_active = FALSE, updated_at = ? 
            WHERE user_id = ?
        ''', (datetime.now().isoformat(), user_id))
        
        # Activate the selected personality
        cursor.execute('''
            UPDATE ai_personalities 
            SET is_active = TRUE, updated_at = ?, usage_count = usage_count + 1
            WHERE id = ? AND user_id = ?
        ''', (datetime.now().isoformat(), personality_id, user_id))
        
        success = cursor.rowcount > 0
        conn.commit()
        conn.close()
        
        if success:
            print(f"✅ Switched to personality {personality_id} for user {user_id}")
        
        return success
    
    async def update_personality(self, user_id: str, personality_id: str, 
                               updates: Dict[str, Any]) -> bool:
        """Update an existing personality."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Build update query dynamically
        update_fields = []
        values = []
        
        allowed_fields = [
            'name', 'description', 'personality_traits', 'communication_style',
            'expertise_domains', 'response_length', 'formality_level',
            'creativity_level', 'empathy_level', 'humor_level',
            'custom_instructions', 'avatar_icon', 'color_theme'
        ]
        
        for field, value in updates.items():
            if field in allowed_fields:
                if field in ['personality_traits', 'expertise_domains']:
                    value = json.dumps(value)
                update_fields.append(f"{field} = ?")
                values.append(value)
        
        if not update_fields:
            return False
        
        update_fields.append("updated_at = ?")
        values.append(datetime.now().isoformat())
        values.extend([personality_id, user_id])
        
        query = f'''
            UPDATE ai_personalities 
            SET {', '.join(update_fields)}
            WHERE id = ? AND user_id = ?
        '''
        
        cursor.execute(query, values)
        success = cursor.rowcount > 0
        conn.commit()
        conn.close()
        
        return success
    
    async def delete_personality(self, user_id: str, personality_id: str) -> bool:
        """Delete a personality."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Don't allow deleting if it's the only personality
        cursor.execute('SELECT COUNT(*) FROM ai_personalities WHERE user_id = ?', (user_id,))
        count = cursor.fetchone()[0]
        
        if count <= 1:
            conn.close()
            return False
        
        cursor.execute('''
            DELETE FROM ai_personalities 
            WHERE id = ? AND user_id = ?
        ''', (personality_id, user_id))
        
        success = cursor.rowcount > 0
        conn.commit()
        conn.close()
        
        return success
    
    
    async def log_personality_usage(self, user_id: str, personality_id: str, 
                                  session_id: str, messages_count: int = 1):
        """Log usage of a personality."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        usage_id = str(uuid.uuid4())
        cursor.execute('''
            INSERT INTO personality_usage 
            (id, user_id, personality_id, session_id, messages_count, used_at)
            VALUES (?, ?, ?, ?, ?, ?)
        ''', (usage_id, user_id, personality_id, session_id, messages_count, datetime.now().isoformat()))
        
        conn.commit()
        conn.close()
    
    async def get_personality_stats(self, user_id: str) -> Dict[str, Any]:
        """Get usage statistics for user's personalities."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        # Get total personalities and usage
        cursor.execute('''
            SELECT 
                COUNT(*) as total_personalities,
                SUM(usage_count) as total_usage,
                AVG(usage_count) as avg_usage
            FROM ai_personalities 
            WHERE user_id = ?
        ''', (user_id,))
        
        stats = cursor.fetchone()
        
        # Get most used personality
        cursor.execute('''
            SELECT name, usage_count 
            FROM ai_personalities 
            WHERE user_id = ? 
            ORDER BY usage_count DESC 
            LIMIT 1
        ''', (user_id,))
        
        most_used = cursor.fetchone()
        
        conn.close()
        
        return {
            "total_personalities": stats[0] or 0,
            "total_usage": stats[1] or 0,
            "average_usage": stats[2] or 0,
            "most_used_personality": {
                "name": most_used[0] if most_used else None,
                "usage_count": most_used[1] if most_used else 0
            }
        }
    
    async def log_personality_usage(self, user_id: str, personality_id: str, session_id: str):
        """Log usage of a personality."""
        try:
            conn = sqlite3.connect(self.db_path)
            cursor = conn.cursor()
            
            usage_id = str(uuid.uuid4())
            cursor.execute('''
                INSERT INTO personality_usage (id, user_id, personality_id, session_id, used_at)
                VALUES (?, ?, ?, ?, ?)
            ''', (usage_id, user_id, personality_id, session_id, datetime.now().isoformat()))
            
            # Update personality usage count
            cursor.execute('''
                UPDATE ai_personalities 
                SET usage_count = usage_count + 1, updated_at = ?
                WHERE id = ?
            ''', (datetime.now().isoformat(), personality_id))
            
            conn.commit()
            conn.close()
            
        except Exception as e:
            print(f"❌ Failed to log personality usage: {e}")
    
    async def build_personality_prompt(self, personality: AIPersonality) -> str:
        """Build a system prompt based on personality characteristics."""
        
        traits_str = ", ".join(personality.personality_traits)
        domains_str = ", ".join(personality.expertise_domains)
        
        formality_desc = "very formal" if personality.formality_level > 0.8 else \
                        "formal" if personality.formality_level > 0.6 else \
                        "casual" if personality.formality_level < 0.3 else "moderately formal"
        
        creativity_desc = "highly creative" if personality.creativity_level > 0.8 else \
                         "creative" if personality.creativity_level > 0.6 else \
                         "practical" if personality.creativity_level < 0.3 else "balanced"
        
        empathy_desc = "very empathetic" if personality.empathy_level > 0.8 else \
                      "empathetic" if personality.empathy_level > 0.6 else \
                      "direct" if personality.empathy_level < 0.3 else "supportive"
        
        humor_desc = "humorous" if personality.humor_level > 0.6 else \
                    "serious" if personality.humor_level < 0.2 else "occasionally witty"
        
        personality_prompt = f"""You are {personality.name}, an AI assistant with the following characteristics:

Description: {personality.description}

Personality Traits: {traits_str}
Communication Style: {personality.communication_style}, {formality_desc}, {creativity_desc}
Emotional Approach: {empathy_desc}, {humor_desc}
Expertise Areas: {domains_str}

Core Behavior Guidelines:
- Respond in a {personality.communication_style} manner with high-quality, thoughtful responses
- Be {formality_desc} in your language while remaining engaging and natural
- Show {empathy_desc} understanding of user needs and context
- Use {creativity_desc} approaches to problem-solving and explanations
- Be {humor_desc} when appropriate to enhance conversation flow
- Draw from your expertise in: {domains_str}
- ALWAYS remember information shared within the current conversation
- Reference previous messages naturally when relevant to show active listening
- Provide complete, well-structured responses without unnecessary repetition
- Maintain consistency in personality and knowledge throughout the conversation

Memory & Context Guidelines:
- Pay close attention to names, personal details, and preferences shared by the user
- Reference earlier parts of the conversation when relevant
- Build upon previous topics naturally
- Remember user's work, interests, and context throughout the chat session

Quality Standards:
- Give complete, helpful responses without cutting off mid-sentence
- Avoid repetitive phrases or responses
- Structure longer responses with clear paragraphs or bullet points when helpful
- Be concise but thorough - quality over quantity

{personality.custom_instructions}

Remember: You are having a real conversation with a person. Listen actively, remember what they tell you, and respond as a knowledgeable, consistent personality who truly engages with their messages."""

        return personality_prompt

# Global personality manager instance
personality_manager = AIPersonalityManager()