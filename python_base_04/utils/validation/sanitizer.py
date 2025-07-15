import re
import html
from typing import Any, Dict, List, Union
from ..exceptions.validation_exceptions import ValidationError
from ..config.config import Config

class Sanitizer:
    """Utility class for sanitizing input data to prevent injection attacks."""
    
    # Regular expressions for validation
    SQL_INJECTION_PATTERNS = [
        r'(?i)(\bSELECT\b|\bINSERT\b|\bUPDATE\b|\bDELETE\b|\bDROP\b|\bUNION\b|\bOR\b|\bAND\b|\bEXEC\b|\bEXECUTE\b|\bTRUNCATE\b|\bALTER\b)',
        r'(?i)(\b--|\b/\*|\b\*/|\b;|\b\'|\b")',
        r'(?i)(\bWAITFOR\b|\bDELAY\b|\bSLEEP\b)',
        r'(?i)(\bXP_CMDSHELL\b|\bSP_OACREATE\b|\bSP_OAMETHOD\b)'
    ]
    
    XSS_PATTERNS = [
        r'<script[^>]*>.*?</script>',
        r'<[^>]+on\w+=[^>]*>',
        r'javascript:[^\s]*',
        r'data:text/html[^>]*',
        r'<iframe[^>]*>',
        r'<object[^>]*>',
        r'<embed[^>]*>',
        r'<applet[^>]*>',
        r'<meta[^>]*>',
        r'<style[^>]*>'
    ]
    
    @staticmethod
    def sanitize_string(value: str, allow_html: bool = False) -> str:
        """
        Sanitize a string input.
        
        Args:
            value: The string to sanitize
            allow_html: Whether to allow HTML content (default False)
            
        Returns:
            str: The sanitized string
            
        Raises:
            ValidationError: If the input contains potentially dangerous content
        """
        if not isinstance(value, str):
            raise ValidationError("Input must be a string")
            
        # Check for SQL injection patterns
        for pattern in Sanitizer.SQL_INJECTION_PATTERNS:
            if re.search(pattern, value):
                raise ValidationError("Input contains potentially dangerous SQL content")
                
        # Check for XSS patterns if HTML is not allowed
        if not allow_html:
            for pattern in Sanitizer.XSS_PATTERNS:
                if re.search(pattern, value, re.IGNORECASE):
                    raise ValidationError("Input contains potentially dangerous HTML/JavaScript content")
                    
            # Escape HTML characters
            value = html.escape(value)
            
        return value.strip()
    
    @staticmethod
    def sanitize_dict(data: Dict[str, Any], allow_html: bool = False) -> Dict[str, Any]:
        """
        Sanitize a dictionary input.
        
        Args:
            data: The dictionary to sanitize
            allow_html: Whether to allow HTML content in string values
            
        Returns:
            Dict[str, Any]: The sanitized dictionary
            
        Raises:
            ValidationError: If the input contains potentially dangerous content
        """
        if not isinstance(data, dict):
            raise ValidationError("Input must be a dictionary")
            
        sanitized = {}
        for key, value in data.items():
            if isinstance(value, str):
                sanitized[key] = Sanitizer.sanitize_string(value, allow_html)
            elif isinstance(value, dict):
                sanitized[key] = Sanitizer.sanitize_dict(value, allow_html)
            elif isinstance(value, list):
                sanitized[key] = Sanitizer.sanitize_list(value, allow_html)
            else:
                sanitized[key] = value
                
        return sanitized
    
    @staticmethod
    def sanitize_list(data: List[Any], allow_html: bool = False) -> List[Any]:
        """
        Sanitize a list input.
        
        Args:
            data: The list to sanitize
            allow_html: Whether to allow HTML content in string values
            
        Returns:
            List[Any]: The sanitized list
            
        Raises:
            ValidationError: If the input contains potentially dangerous content
        """
        if not isinstance(data, list):
            raise ValidationError("Input must be a list")
            
        sanitized = []
        for item in data:
            if isinstance(item, str):
                sanitized.append(Sanitizer.sanitize_string(item, allow_html))
            elif isinstance(item, dict):
                sanitized.append(Sanitizer.sanitize_dict(item, allow_html))
            elif isinstance(item, list):
                sanitized.append(Sanitizer.sanitize_list(item, allow_html))
            else:
                sanitized.append(item)
                
        return sanitized
    
    @staticmethod
    def sanitize_json(data: Union[Dict[str, Any], List[Any]], allow_html: bool = False) -> Union[Dict[str, Any], List[Any]]:
        """
        Sanitize JSON-like data (dict or list).
        
        Args:
            data: The JSON data to sanitize
            allow_html: Whether to allow HTML content in string values
            
        Returns:
            Union[Dict[str, Any], List[Any]]: The sanitized data
            
        Raises:
            ValidationError: If the input contains potentially dangerous content
        """
        if isinstance(data, dict):
            return Sanitizer.sanitize_dict(data, allow_html)
        elif isinstance(data, list):
            return Sanitizer.sanitize_list(data, allow_html)
        else:
            raise ValidationError("Input must be a dictionary or list") 