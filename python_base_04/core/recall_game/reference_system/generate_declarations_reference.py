#!/usr/bin/env python3
"""
Declarations Reference Generator

This script automatically generates an HTML reference page from all YAML declarations
in the Recall game system. It scans all YAML files and creates a comprehensive,
searchable reference document.
"""

import os
import yaml
import json
from pathlib import Path
from typing import Dict, Any, List
from datetime import datetime
import re


class DeclarationsReferenceGenerator:
    """Generates HTML reference from YAML declarations"""
    
    def __init__(self, base_path: str = None):
        self.base_path = base_path or self._get_default_base_path()
        self.output_path = os.path.join(self.base_path, "declarations_reference.html")
        self.declarations = {}
        
    def _get_default_base_path(self) -> str:
        """Get the default base path for game rules"""
        current_dir = Path(__file__).parent
        return str(current_dir.parent / "game_rules")
    
    def scan_declarations(self) -> Dict[str, Any]:
        """Scan all YAML files and load declarations"""
        declarations = {
            'actions': {},
            'cards': {},
            'special_powers': {},
            'ai_logic': {}
        }
        
        # Scan actions
        actions_path = os.path.join(self.base_path, "actions")
        if os.path.exists(actions_path):
            for filename in os.listdir(actions_path):
                if filename.endswith(('.yaml', '.yml')):
                    rule_name = filename[:-5] if filename.endswith('.yaml') else filename[:-4]
                    file_path = os.path.join(actions_path, filename)
                    declarations['actions'][rule_name] = self._load_yaml_file(file_path)
        
        # Scan cards
        cards_path = os.path.join(self.base_path, "cards")
        if os.path.exists(cards_path):
            for filename in os.listdir(cards_path):
                if filename.endswith(('.yaml', '.yml')):
                    rule_name = filename[:-5] if filename.endswith('.yaml') else filename[:-4]
                    file_path = os.path.join(cards_path, filename)
                    declarations['cards'][rule_name] = self._load_yaml_file(file_path)
        
        # Scan special powers
        special_powers_path = os.path.join(self.base_path, "special_powers")
        if os.path.exists(special_powers_path):
            for filename in os.listdir(special_powers_path):
                if filename.endswith(('.yaml', '.yml')):
                    rule_name = filename[:-5] if filename.endswith('.yaml') else filename[:-4]
                    file_path = os.path.join(special_powers_path, filename)
                    declarations['special_powers'][rule_name] = self._load_yaml_file(file_path)
        
        # Scan AI logic
        ai_logic_path = os.path.join(self.base_path, "ai_logic")
        if os.path.exists(ai_logic_path):
            for difficulty in os.listdir(ai_logic_path):
                difficulty_path = os.path.join(ai_logic_path, difficulty)
                if os.path.isdir(difficulty_path):
                    declarations['ai_logic'][difficulty] = {}
                    for filename in os.listdir(difficulty_path):
                        if filename.endswith(('.yaml', '.yml')):
                            rule_name = filename[:-5] if filename.endswith('.yaml') else filename[:-4]
                            file_path = os.path.join(difficulty_path, filename)
                            declarations['ai_logic'][difficulty][rule_name] = self._load_yaml_file(file_path)
        
        self.declarations = declarations
        return declarations
    
    def _load_yaml_file(self, file_path: str) -> Dict[str, Any]:
        """Load a YAML file safely"""
        try:
            with open(file_path, 'r', encoding='utf-8') as file:
                return yaml.safe_load(file) or {}
        except Exception as e:
            return {'error': f'Failed to load {file_path}: {str(e)}'}
    
    def generate_html(self) -> str:
        """Generate the complete HTML reference page"""
        html = self._get_html_header()
        html += self._get_navigation()
        html += self._get_search_section()
        html += self._get_overview_section()
        html += self._get_actions_section()
        html += self._get_cards_section()
        html += self._get_special_powers_section()
        html += self._get_ai_logic_section()
        html += self._get_placeholders_section()
        html += self._get_effects_section()
        html += self._get_validation_section()
        html += self._get_triggers_section()
        html += self._get_html_footer()
        
        return html
    
    def _get_html_header(self) -> str:
        """Generate HTML header with CSS and JavaScript"""
        return f"""
<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Recall Game Declarations Reference</title>
    <style>
        * {{
            margin: 0;
            padding: 0;
            box-sizing: border-box;
        }}
        
        body {{
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif;
            line-height: 1.6;
            color: #333;
            background-color: #f8f9fa;
        }}
        
        .container {{
            max-width: 1200px;
            margin: 0 auto;
            padding: 20px;
        }}
        
        .header {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 2rem 0;
            text-align: center;
            margin-bottom: 2rem;
            border-radius: 10px;
        }}
        
        .header h1 {{
            font-size: 2.5rem;
            margin-bottom: 0.5rem;
        }}
        
        .header p {{
            font-size: 1.1rem;
            opacity: 0.9;
        }}
        
        .nav {{
            background: white;
            padding: 1rem;
            border-radius: 8px;
            margin-bottom: 2rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        
        .nav ul {{
            list-style: none;
            display: flex;
            flex-wrap: wrap;
            gap: 1rem;
        }}
        
        .nav a {{
            text-decoration: none;
            color: #667eea;
            padding: 0.5rem 1rem;
            border-radius: 5px;
            transition: background-color 0.3s;
        }}
        
        .nav a:hover {{
            background-color: #f0f2ff;
        }}
        
        .search-section {{
            background: white;
            padding: 1.5rem;
            border-radius: 8px;
            margin-bottom: 2rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        
        .search-input {{
            width: 100%;
            padding: 0.8rem;
            border: 2px solid #e0e0e0;
            border-radius: 5px;
            font-size: 1rem;
            transition: border-color 0.3s;
        }}
        
        .search-input:focus {{
            outline: none;
            border-color: #667eea;
        }}
        
        .section {{
            background: white;
            padding: 2rem;
            border-radius: 8px;
            margin-bottom: 2rem;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }}
        
        .section h2 {{
            color: #667eea;
            margin-bottom: 1rem;
            padding-bottom: 0.5rem;
            border-bottom: 2px solid #f0f2ff;
        }}
        
        .declaration-card {{
            border: 1px solid #e0e0e0;
            border-radius: 8px;
            padding: 1.5rem;
            margin-bottom: 1rem;
            transition: box-shadow 0.3s;
        }}
        
        .declaration-card:hover {{
            box-shadow: 0 4px 15px rgba(0,0,0,0.1);
        }}
        
        .declaration-title {{
            font-size: 1.3rem;
            font-weight: bold;
            color: #333;
            margin-bottom: 0.5rem;
        }}
        
        .declaration-type {{
            display: inline-block;
            background: #667eea;
            color: white;
            padding: 0.2rem 0.5rem;
            border-radius: 3px;
            font-size: 0.8rem;
            margin-bottom: 1rem;
        }}
        
        .yaml-content {{
            background: #f8f9fa;
            border: 1px solid #e0e0e0;
            border-radius: 5px;
            padding: 1rem;
            font-family: 'Courier New', monospace;
            font-size: 0.9rem;
            overflow-x: auto;
            white-space: pre-wrap;
        }}
        
        .placeholder {{
            background: #fff3cd;
            color: #856404;
            padding: 0.1rem 0.3rem;
            border-radius: 3px;
            font-family: 'Courier New', monospace;
        }}
        
        .effect-type {{
            background: #d1ecf1;
            color: #0c5460;
            padding: 0.2rem 0.5rem;
            border-radius: 3px;
            font-size: 0.8rem;
            margin-right: 0.5rem;
        }}
        
        .validation-type {{
            background: #d4edda;
            color: #155724;
            padding: 0.2rem 0.5rem;
            border-radius: 3px;
            font-size: 0.8rem;
            margin-right: 0.5rem;
        }}
        
        .trigger-condition {{
            background: #f8d7da;
            color: #721c24;
            padding: 0.2rem 0.5rem;
            border-radius: 3px;
            font-size: 0.8rem;
            margin-right: 0.5rem;
        }}
        
        .hidden {{
            display: none;
        }}
        
        .highlight {{
            background: #fff3cd;
            border-radius: 3px;
            padding: 0.1rem 0.2rem;
        }}
        
        .stats {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
            gap: 1rem;
            margin-bottom: 2rem;
        }}
        
        .stat-card {{
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
            color: white;
            padding: 1.5rem;
            border-radius: 8px;
            text-align: center;
        }}
        
        .stat-number {{
            font-size: 2rem;
            font-weight: bold;
            margin-bottom: 0.5rem;
        }}
        
        .stat-label {{
            font-size: 0.9rem;
            opacity: 0.9;
        }}
        
        @media (max-width: 768px) {{
            .nav ul {{
                flex-direction: column;
            }}
            
            .stats {{
                grid-template-columns: 1fr;
            }}
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🎮 Recall Game Declarations Reference</h1>
            <p>Complete reference for all YAML declarations in the Recall game system</p>
            <p><small>Generated on {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}</small></p>
        </div>
"""
    
    def _get_navigation(self) -> str:
        """Generate navigation menu"""
        return """
        <nav class="nav">
            <ul>
                <li><a href="#overview">Overview</a></li>
                <li><a href="#actions">Actions</a></li>
                <li><a href="#cards">Cards</a></li>
                <li><a href="#special-powers">Special Powers</a></li>
                <li><a href="#ai-logic">AI Logic</a></li>
                <li><a href="#placeholders">Placeholders</a></li>
                <li><a href="#effects">Effects</a></li>
                <li><a href="#validation">Validation</a></li>
                <li><a href="#triggers">Triggers</a></li>
            </ul>
        </nav>
"""
    
    def _get_search_section(self) -> str:
        """Generate search functionality"""
        return """
        <div class="search-section">
            <h2>🔍 Search Declarations</h2>
            <input type="text" id="searchInput" class="search-input" placeholder="Search for declarations, effects, validations, placeholders...">
            <p><small>Type to filter declarations. Search is case-insensitive and matches any part of the declaration.</small></p>
        </div>
"""
    
    def _get_overview_section(self) -> str:
        """Generate overview section with statistics"""
        total_actions = len(self.declarations.get('actions', {}))
        total_cards = len(self.declarations.get('cards', {}))
        total_special_powers = len(self.declarations.get('special_powers', {}))
        total_ai_difficulties = len(self.declarations.get('ai_logic', {}))
        
        return f"""
        <div class="section" id="overview">
            <h2>📊 Overview</h2>
            <div class="stats">
                <div class="stat-card">
                    <div class="stat-number">{total_actions}</div>
                    <div class="stat-label">Action Rules</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">{total_cards}</div>
                    <div class="stat-label">Card Rules</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">{total_special_powers}</div>
                    <div class="stat-label">Special Powers</div>
                </div>
                <div class="stat-card">
                    <div class="stat-number">{total_ai_difficulties}</div>
                    <div class="stat-label">AI Difficulties</div>
                </div>
            </div>
            <p>This reference contains all YAML declarations used in the Recall game system. Each declaration defines specific game logic, rules, and behaviors that are processed by the GameLogicEngine.</p>
        </div>
"""
    
    def _get_actions_section(self) -> str:
        """Generate actions section"""
        html = """
        <div class="section" id="actions">
            <h2>🎯 Action Rules</h2>
            <p>Action rules define how player actions are processed and what effects they trigger.</p>
        """
        
        for action_name, action_data in self.declarations.get('actions', {}).items():
            html += self._generate_declaration_card(
                action_name, 
                action_data, 
                'action',
                f"Defines how the '{action_name}' action is processed"
            )
        
        html += "</div>"
        return html
    
    def _get_cards_section(self) -> str:
        """Generate cards section"""
        html = """
        <div class="section" id="cards">
            <h2>🃏 Card Rules</h2>
            <p>Card rules define special abilities and behaviors for specific card types.</p>
        """
        
        for card_name, card_data in self.declarations.get('cards', {}).items():
            html += self._generate_declaration_card(
                card_name, 
                card_data, 
                'card',
                f"Defines special abilities for {card_name} cards"
            )
        
        html += "</div>"
        return html
    
    def _get_special_powers_section(self) -> str:
        """Generate special powers section"""
        html = """
        <div class="section" id="special-powers">
            <h2>⚡ Special Power Rules</h2>
            <p>Special power rules define additional abilities beyond standard card powers.</p>
        """
        
        for power_name, power_data in self.declarations.get('special_powers', {}).items():
            html += self._generate_declaration_card(
                power_name, 
                power_data, 
                'special_power',
                f"Defines the '{power_name}' special power ability"
            )
        
        html += "</div>"
        return html
    
    def _get_ai_logic_section(self) -> str:
        """Generate AI logic section"""
        html = """
        <div class="section" id="ai-logic">
            <h2>🤖 AI Logic Rules</h2>
            <p>AI logic rules define how computer players make decisions based on difficulty level.</p>
        """
        
        for difficulty, rules in self.declarations.get('ai_logic', {}).items():
            html += f"""
            <h3>Difficulty: {difficulty.title()}</h3>
            """
            
            for rule_name, rule_data in rules.items():
                html += self._generate_declaration_card(
                    f"{difficulty}/{rule_name}", 
                    rule_data, 
                    'ai_logic',
                    f"AI decision logic for {difficulty} difficulty - {rule_name}"
                )
        
        html += "</div>"
        return html
    
    def _get_placeholders_section(self) -> str:
        """Generate placeholders reference section"""
        placeholders = {
            "player_id": "The ID of the player performing the action",
            "card_id": "The ID of the card being played",
            "card_rank": "The rank of the card (ace, king, queen, etc.)",
            "out_of_turn": "Whether the action is being performed out of turn",
            "card_data": "Complete card information object",
            "target_player_id": "ID of the target player for special powers",
            "card_position": "Position of the card in hand",
            "game_id": "ID of the current game"
        }
        
        html = """
        <div class="section" id="placeholders">
            <h2>🔗 Placeholders</h2>
            <p>Placeholders are dynamic values that are replaced with actual data during rule processing.</p>
        """
        
        for placeholder, description in placeholders.items():
            html += f"""
            <div class="declaration-card">
                <div class="declaration-title">
                    <span class="placeholder">{{{placeholder}}}</span>
                </div>
                <p>{description}</p>
            </div>
            """
        
        html += "</div>"
        return html
    
    def _get_effects_section(self) -> str:
        """Generate effects reference section"""
        effects = {
            "move_card_to_discard": "Move a card from player's hand to discard pile",
            "replace_card_in_hand": "Draw a new card to replace the played card",
            "check_special_power": "Check if a played card has special power and trigger it",
            "check_recall_opportunity": "Check if player can call Recall",
            "next_player": "Move to the next player's turn",
            "show_card_to_player": "Reveal a card to a specific player",
            "switch_cards": "Switch two cards between players",
            "move_card": "Move a card from one player to another"
        }
        
        html = """
        <div class="section" id="effects">
            <h2>✨ Effects</h2>
            <p>Effects are state changes that occur when rules are executed.</p>
        """
        
        for effect, description in effects.items():
            html += f"""
            <div class="declaration-card">
                <div class="declaration-title">
                    <span class="effect-type">{effect}</span>
                </div>
                <p>{description}</p>
            </div>
            """
        
        html += "</div>"
        return html
    
    def _get_validation_section(self) -> str:
        """Generate validation reference section"""
        validations = {
            "player_has_card": "Check if player has a specific card",
            "card_is_playable": "Check if a card can be played",
            "is_player_turn": "Check if it's the player's turn",
            "card_in_hand": "Check if player has a card of specific rank",
            "target_player_has_cards": "Check if target player has cards to interact with"
        }
        
        html = """
        <div class="section" id="validation">
            <h2>✅ Validation</h2>
            <p>Validation checks ensure actions are legal before execution.</p>
        """
        
        for validation, description in validations.items():
            html += f"""
            <div class="declaration-card">
                <div class="declaration-title">
                    <span class="validation-type">{validation}</span>
                </div>
                <p>{description}</p>
            </div>
            """
        
        html += "</div>"
        return html
    
    def _get_triggers_section(self) -> str:
        """Generate triggers reference section"""
        triggers = {
            "is_player_turn": "Action is performed during player's turn",
            "same_rank_card": "Action is performed with a card of the same rank as last played",
            "recall_called": "Recall has been called and final round is active",
            "is_my_turn": "AI decision is made during AI player's turn",
            "has_low_point_card": "Player has cards with low point values",
            "has_special_power_card": "Player has cards with special powers",
            "power_is_useful": "Special power would be beneficial in current situation",
            "can_call_recall": "Player is eligible to call Recall",
            "advantageous_position": "Player is in a good position to win"
        }
        
        html = """
        <div class="section" id="triggers">
            <h2>🎯 Triggers</h2>
            <p>Triggers determine when rules and conditions are activated.</p>
        """
        
        for trigger, description in triggers.items():
            html += f"""
            <div class="declaration-card">
                <div class="declaration-title">
                    <span class="trigger-condition">{trigger}</span>
                </div>
                <p>{description}</p>
            </div>
            """
        
        html += "</div>"
        return html
    
    def _generate_declaration_card(self, name: str, data: Dict[str, Any], decl_type: str, description: str) -> str:
        """Generate a declaration card HTML"""
        yaml_content = yaml.dump(data, default_flow_style=False, indent=2)
        
        # Highlight placeholders in YAML content
        yaml_content = re.sub(r'\{([^}]+)\}', r'<span class="placeholder">{\1}</span>', yaml_content)
        
        return f"""
        <div class="declaration-card" data-type="{decl_type}" data-name="{name.lower()}">
            <div class="declaration-title">{name}</div>
            <div class="declaration-type">{decl_type.replace('_', ' ').title()}</div>
            <p>{description}</p>
            <details>
                <summary>View YAML Declaration</summary>
                <div class="yaml-content">{yaml_content}</div>
            </details>
        </div>
        """
    
    def _get_html_footer(self) -> str:
        """Generate HTML footer with JavaScript"""
        return """
        <script>
            // Search functionality
            document.getElementById('searchInput').addEventListener('input', function() {
                const searchTerm = this.value.toLowerCase();
                const cards = document.querySelectorAll('.declaration-card');
                
                cards.forEach(card => {
                    const text = card.textContent.toLowerCase();
                    const name = card.getAttribute('data-name');
                    const type = card.getAttribute('data-type');
                    
                    if (text.includes(searchTerm) || name.includes(searchTerm) || type.includes(searchTerm)) {
                        card.classList.remove('hidden');
                        // Highlight search term
                        if (searchTerm) {
                            const title = card.querySelector('.declaration-title');
                            title.innerHTML = title.innerHTML.replace(
                                new RegExp(searchTerm, 'gi'),
                                match => `<span class="highlight">${match}</span>`
                            );
                        }
                    } else {
                        card.classList.add('hidden');
                    }
                });
            });
            
            // Smooth scrolling for navigation
            document.querySelectorAll('nav a').forEach(anchor => {
                anchor.addEventListener('click', function(e) {
                    e.preventDefault();
                    const targetId = this.getAttribute('href').substring(1);
                    const targetElement = document.getElementById(targetId);
                    if (targetElement) {
                        targetElement.scrollIntoView({ behavior: 'smooth' });
                    }
                });
            });
            
            // Auto-expand search results
            document.getElementById('searchInput').addEventListener('input', function() {
                const searchTerm = this.value.toLowerCase();
                if (searchTerm.length > 2) {
                    document.querySelectorAll('details').forEach(detail => {
                        detail.open = true;
                    });
                }
            });
        </script>
    </body>
</html>
"""
    
    def generate_and_save(self) -> str:
        """Generate and save the HTML reference file"""
        self.scan_declarations()
        html_content = self.generate_html()
        
        with open(self.output_path, 'w', encoding='utf-8') as file:
            file.write(html_content)
        
        print(f"✅ Declarations reference generated: {self.output_path}")
        print(f"📊 Found {len(self.declarations.get('actions', {}))} action rules")
        print(f"🃏 Found {len(self.declarations.get('cards', {}))} card rules")
        print(f"⚡ Found {len(self.declarations.get('special_powers', {}))} special power rules")
        print(f"🤖 Found {len(self.declarations.get('ai_logic', {}))} AI difficulty levels")
        
        return self.output_path


def main():
    """Main function to generate the reference"""
    generator = DeclarationsReferenceGenerator()
    output_path = generator.generate_and_save()
    
    print(f"\n🌐 Open {output_path} in your browser to view the reference")
    print("📝 The reference will automatically update when you add new YAML declarations")


if __name__ == "__main__":
    main() 