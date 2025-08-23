"""
YAML Loader for Recall Game Rules

This module provides functionality to load declarative game rules from YAML files.
"""

import os
import yaml
from typing import Dict, Any, List
from pathlib import Path
from tools.logger.custom_logging import custom_log


class YAMLLoader:
    """Loads YAML configuration files for game rules"""
    
    def __init__(self, base_path: str = None):
        self.base_path = base_path or self._get_default_base_path()
    
    def _get_default_base_path(self) -> str:
        """Get the default base path for game rules"""
        current_dir = Path(__file__).parent
        return str(current_dir.parent / "game_rules")
    
    def load_rules(self, rules_dir: str) -> Dict[str, Any]:
        """Load all rules from a directory"""
        rules = {}
        full_path = os.path.join(self.base_path, rules_dir)
        
        if not os.path.exists(full_path):
            return rules
        
        for filename in os.listdir(full_path):
            if filename.endswith('.yaml') or filename.endswith('.yml'):
                rule_name = filename[:-5] if filename.endswith('.yaml') else filename[:-4]
                rule_path = os.path.join(full_path, filename)
                
                try:
                    with open(rule_path, 'r', encoding='utf-8') as file:
                        rule_data = yaml.safe_load(file)
                        rules[rule_name] = rule_data
                        
                        # Log the parsed YAML data
                        custom_log(f"📄 [YAMLLoader] Loaded rule '{rule_name}': {list(rule_data.keys()) if rule_data else 'empty'}")
                        
                except Exception as e:
                    custom_log(f"❌ [YAMLLoader] Error loading rule {filename}: {e}", level="ERROR")
        
        custom_log(f"📁 [YAMLLoader] Loaded {len(rules)} rules from '{rules_dir}': {list(rules.keys())}")
        return rules
    
    def load_single_rule(self, rule_path: str) -> Dict[str, Any]:
        """Load a single rule file"""
        full_path = os.path.join(self.base_path, rule_path)
        
        if not os.path.exists(full_path):
            return {}
        
        try:
            with open(full_path, 'r', encoding='utf-8') as file:
                rule_data = yaml.safe_load(file)
                
                # Log the parsed YAML data
                custom_log(f"📄 [YAMLLoader] Loaded single rule '{rule_path}': {list(rule_data.keys()) if rule_data else 'empty'}")
                
                return rule_data
        except Exception as e:
            custom_log(f"❌ [YAMLLoader] Error loading rule {rule_path}: {e}", level="ERROR")
            return {}
    
    def load_action_rules(self) -> Dict[str, Any]:
        """Load action rules"""
        return self.load_rules("actions")
    
    def load_card_rules(self) -> Dict[str, Any]:
        """Load card rules"""
        return self.load_rules("cards")
    
    def load_special_power_rules(self) -> Dict[str, Any]:
        """Load special power rules"""
        return self.load_rules("special_powers")
    
    def load_ai_rules(self, difficulty: str) -> Dict[str, Any]:
        """Load AI rules for a specific difficulty"""
        return self.load_rules(f"ai_logic/{difficulty}")
    
    def save_rule(self, rule_name: str, rule_data: Dict[str, Any], rules_dir: str = "actions"):
        """Save a rule to a YAML file"""
        full_path = os.path.join(self.base_path, rules_dir)
        os.makedirs(full_path, exist_ok=True)
        
        file_path = os.path.join(full_path, f"{rule_name}.yaml")
        
        try:
            with open(file_path, 'w', encoding='utf-8') as file:
                yaml.dump(rule_data, file, default_flow_style=False, indent=2)
            return True
        except Exception as e:
            print(f"Error saving rule {rule_name}: {e}")
            return False
    
    def list_available_rules(self, rules_dir: str = None) -> List[str]:
        """List all available rules in a directory"""
        if rules_dir:
            full_path = os.path.join(self.base_path, rules_dir)
        else:
            full_path = self.base_path
        
        if not os.path.exists(full_path):
            return []
        
        rules = []
        for filename in os.listdir(full_path):
            if filename.endswith('.yaml') or filename.endswith('.yml'):
                rule_name = filename[:-5] if filename.endswith('.yaml') else filename[:-4]
                rules.append(rule_name)
        
        return rules 