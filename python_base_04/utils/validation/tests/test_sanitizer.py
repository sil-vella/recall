import pytest
from ..sanitizer import Sanitizer
from ...exceptions.validation_exceptions import ValidationError

class TestSanitizer:
    """Test cases for Sanitizer class."""
    
    def test_sanitize_string_valid(self):
        """Test sanitization of valid strings."""
        # Test basic string
        assert Sanitizer.sanitize_string("test") == "test"
        
        # Test string with spaces
        assert Sanitizer.sanitize_string(" test ") == "test"
        
        # Test string with HTML when allowed
        html_string = "<div>test</div>"
        assert Sanitizer.sanitize_string(html_string, allow_html=True) == html_string
    
    def test_sanitize_string_invalid(self):
        """Test sanitization of invalid strings."""
        # Test SQL injection attempts
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_string("SELECT * FROM users")
        assert "SQL content" in str(exc_info.value)
        
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_string("DROP TABLE users")
        assert "SQL content" in str(exc_info.value)
        
        # Test XSS attempts
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_string("<script>alert('xss')</script>")
        assert "HTML/JavaScript content" in str(exc_info.value)
        
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_string("<img src=x onerror=alert('xss')>")
        assert "HTML/JavaScript content" in str(exc_info.value)
        
        # Test non-string input
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_string(123)
        assert "must be a string" in str(exc_info.value)
    
    def test_sanitize_dict_valid(self):
        """Test sanitization of valid dictionaries."""
        # Test basic dictionary
        data = {
            "name": "test",
            "description": "test description"
        }
        assert Sanitizer.sanitize_dict(data) == data
        
        # Test nested dictionary
        nested_data = {
            "user": {
                "name": "test",
                "profile": {
                    "bio": "test bio"
                }
            }
        }
        assert Sanitizer.sanitize_dict(nested_data) == nested_data
        
        # Test dictionary with lists
        data_with_lists = {
            "tags": ["test", "example"],
            "nested": {
                "items": ["item1", "item2"]
            }
        }
        assert Sanitizer.sanitize_dict(data_with_lists) == data_with_lists
    
    def test_sanitize_dict_invalid(self):
        """Test sanitization of invalid dictionaries."""
        # Test dictionary with SQL injection
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_dict({"query": "SELECT * FROM users"})
        assert "SQL content" in str(exc_info.value)
        
        # Test dictionary with XSS
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_dict({"content": "<script>alert('xss')</script>"})
        assert "HTML/JavaScript content" in str(exc_info.value)
        
        # Test non-dict input
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_dict("not a dict")
        assert "must be a dictionary" in str(exc_info.value)
    
    def test_sanitize_list_valid(self):
        """Test sanitization of valid lists."""
        # Test basic list
        assert Sanitizer.sanitize_list(["test", "example"]) == ["test", "example"]
        
        # Test list with dictionaries
        data = [
            {"name": "test1"},
            {"name": "test2"}
        ]
        assert Sanitizer.sanitize_list(data) == data
        
        # Test nested lists
        nested = [
            ["test1", "test2"],
            ["test3", "test4"]
        ]
        assert Sanitizer.sanitize_list(nested) == nested
    
    def test_sanitize_list_invalid(self):
        """Test sanitization of invalid lists."""
        # Test list with SQL injection
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_list(["test", "SELECT * FROM users"])
        assert "SQL content" in str(exc_info.value)
        
        # Test list with XSS
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_list(["test", "<script>alert('xss')</script>"])
        assert "HTML/JavaScript content" in str(exc_info.value)
        
        # Test non-list input
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_list("not a list")
        assert "must be a list" in str(exc_info.value)
    
    def test_sanitize_json_valid(self):
        """Test sanitization of valid JSON data."""
        # Test dictionary
        data = {"name": "test"}
        assert Sanitizer.sanitize_json(data) == data
        
        # Test list
        data = ["test", "example"]
        assert Sanitizer.sanitize_json(data) == data
    
    def test_sanitize_json_invalid(self):
        """Test sanitization of invalid JSON data."""
        # Test non-JSON input
        with pytest.raises(ValidationError) as exc_info:
            Sanitizer.sanitize_json("not json")
        assert "must be a dictionary or list" in str(exc_info.value) 