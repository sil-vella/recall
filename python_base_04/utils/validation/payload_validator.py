import json
from typing import Any, Dict, List, Union
from ..exceptions.validation_exceptions import ValidationError
from ..config.config import Config

class PayloadValidator:
    """Utility class for validating payload size and format."""
    
    @staticmethod
    def validate_size(payload: Union[str, Dict, List], max_size: int) -> None:
        """
        Validate payload size.
        
        Args:
            payload: The payload to validate
            max_size: Maximum allowed size in bytes
            
        Raises:
            ValidationError: If payload is too large
        """
        if isinstance(payload, str):
            size = len(payload.encode('utf-8'))
        else:
            size = len(json.dumps(payload).encode('utf-8'))
            
        if size > max_size:
            raise ValidationError(f"Payload too large ({size} bytes). Maximum allowed: {max_size} bytes")
    
    @staticmethod
    def validate_json_format(payload: str) -> Union[Dict, List]:
        """
        Validate JSON format and parse.
        
        Args:
            payload: JSON string to validate
            
        Returns:
            Union[Dict, List]: Parsed JSON data
            
        Raises:
            ValidationError: If JSON is malformed
        """
        try:
            return json.loads(payload)
        except json.JSONDecodeError as e:
            raise ValidationError(f"Invalid JSON format: {str(e)}")
    
    @staticmethod
    def validate_structure(data: Union[Dict, List], required_fields: Dict[str, type] = None) -> None:
        """
        Validate payload structure and field types.
        
        Args:
            data: The data to validate
            required_fields: Dictionary of required fields and their types
            
        Raises:
            ValidationError: If structure is invalid
        """
        if not isinstance(data, (dict, list)):
            raise ValidationError("Payload must be a JSON object or array")
            
        if required_fields and isinstance(data, dict):
            for field, field_type in required_fields.items():
                if field not in data:
                    raise ValidationError(f"Missing required field: {field}")
                    
                if not isinstance(data[field], field_type):
                    raise ValidationError(f"Field '{field}' must be of type {field_type.__name__}")
    
    @staticmethod
    def validate_nested_depth(data: Union[Dict, List], max_depth: int, current_depth: int = 0) -> None:
        """
        Validate maximum nesting depth of payload.
        
        Args:
            data: The data to validate
            max_depth: Maximum allowed nesting depth
            current_depth: Current nesting depth (internal use)
            
        Raises:
            ValidationError: If nesting is too deep
        """
        if current_depth > max_depth:
            raise ValidationError(f"Payload nesting too deep (max {max_depth} levels)")
            
        if isinstance(data, dict):
            for value in data.values():
                if isinstance(value, (dict, list)):
                    PayloadValidator.validate_nested_depth(value, max_depth, current_depth + 1)
        elif isinstance(data, list):
            for item in data:
                if isinstance(item, (dict, list)):
                    PayloadValidator.validate_nested_depth(item, max_depth, current_depth + 1)
    
    @staticmethod
    def validate_payload(payload: str, max_size: int, required_fields: Dict[str, type] = None, max_depth: int = 10) -> Union[Dict, List]:
        """
        Comprehensive payload validation.
        
        Args:
            payload: JSON string to validate
            max_size: Maximum allowed size in bytes
            required_fields: Dictionary of required fields and their types
            max_depth: Maximum allowed nesting depth
            
        Returns:
            Union[Dict, List]: Validated and parsed payload
            
        Raises:
            ValidationError: If validation fails
        """
        # Validate size
        PayloadValidator.validate_size(payload, max_size)
        
        # Parse and validate JSON format
        data = PayloadValidator.validate_json_format(payload)
        
        # Validate structure
        PayloadValidator.validate_structure(data, required_fields)
        
        # Validate nesting depth
        PayloadValidator.validate_nested_depth(data, max_depth)
        
        return data 