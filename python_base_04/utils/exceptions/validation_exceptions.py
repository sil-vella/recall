class ValidationError(Exception):
    """Exception raised for validation errors in credit operations."""
    
    def __init__(self, message: str):
        """
        Initialize the validation error.
        
        Args:
            message: The error message
        """
        self.message = message
        super().__init__(self.message) 