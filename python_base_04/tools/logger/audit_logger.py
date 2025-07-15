import os
import json
import glob
import gzip
from datetime import datetime
from typing import Dict, Any, Optional
from .custom_logging import custom_log, sanitize_log_message

class AuditLogger:
    """Class for handling audit logging of credit system transactions."""
    
    # Audit log file configuration
    AUDIT_LOG_FILE = 'credit_audit.log'
    AUDIT_LOG_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), AUDIT_LOG_FILE)
    
    # Log rotation settings
    MAX_FILE_SIZE = 100 * 1024 * 1024  # 100MB
    MAX_FILES = 10  # Keep last 10 rotated files
    
    # Log compression settings
    COMPRESS_AFTER_DAYS = 30  # Compress logs older than 30 days
    
    # Minimum retention period in days
    RETENTION_DAYS = 365
    
    @staticmethod
    def rotate_log() -> None:
        """Rotate the log file if it exceeds the maximum size."""
        if os.path.exists(AuditLogger.AUDIT_LOG_PATH):
            size = os.path.getsize(AuditLogger.AUDIT_LOG_PATH)
            if size >= AuditLogger.MAX_FILE_SIZE:
                # Rename current file with timestamp
                timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
                rotated_file = f"{AuditLogger.AUDIT_LOG_PATH}.{timestamp}"
                os.rename(AuditLogger.AUDIT_LOG_PATH, rotated_file)
                
                # Clean up old files if we exceed MAX_FILES
                log_files = sorted(glob.glob(f"{AuditLogger.AUDIT_LOG_PATH}.*"))
                if len(log_files) > AuditLogger.MAX_FILES:
                    for old_file in log_files[:-AuditLogger.MAX_FILES]:
                        os.remove(old_file)
    
    @staticmethod
    def compress_old_logs() -> None:
        """Compress log files older than COMPRESS_AFTER_DAYS."""
        log_files = glob.glob(f"{AuditLogger.AUDIT_LOG_PATH}.*")
        for log_file in log_files:
            # Skip already compressed files
            if log_file.endswith('.gz'):
                continue
                
            # Extract timestamp from filename
            timestamp_str = log_file.split('.')[-1]
            try:
                file_date = datetime.strptime(timestamp_str, "%Y%m%d_%H%M%S")
                if (datetime.now() - file_date).days > AuditLogger.COMPRESS_AFTER_DAYS:
                    # Compress the file
                    with open(log_file, 'rb') as f_in:
                        with gzip.open(f"{log_file}.gz", 'wb') as f_out:
                            f_out.writelines(f_in)
                    os.remove(log_file)  # Remove original after compression
            except ValueError:
                continue  # Skip files that don't match our naming pattern
    
    @staticmethod
    def _write_to_log(entry: Dict[str, Any], prefix: str) -> None:
        """Internal method to write log entries with rotation and compression."""
        # Check if we need to rotate
        AuditLogger.rotate_log()
        
        # Sanitize and format the entry
        sanitized_entry = sanitize_log_message(json.dumps(entry))
        log_message = f"[{prefix}] {sanitized_entry}"
        
        # Write to log file
        with open(AuditLogger.AUDIT_LOG_PATH, 'a') as f:
            f.write(f"{log_message}\n")
        
        # Check for old logs to compress
        AuditLogger.compress_old_logs()
        
        # Also log to custom_log
        custom_log(log_message)
    
    @staticmethod
    def log_transaction(
        transaction_id: str,
        user_id: str,
        action_type: str,
        credit_delta: float,
        source: Dict[str, Any],
        metadata: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Log a credit transaction with all relevant details.
        
        Args:
            transaction_id: Unique identifier for the transaction
            user_id: ID of the user involved in the transaction
            action_type: Type of transaction (e.g., 'purchase', 'reward', 'burn')
            credit_delta: Change in credit amount (positive for addition, negative for deduction)
            source: Dictionary containing source information (service, IP, client)
            metadata: Optional additional metadata about the transaction
        """
        audit_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'transaction_id': transaction_id,
            'user_id': user_id,
            'action_type': action_type,
            'credit_delta': credit_delta,
            'source': source,
            'metadata': metadata or {}
        }
        
        AuditLogger._write_to_log(audit_entry, "AUDIT")
    
    @staticmethod
    def log_balance_change(
        user_id: str,
        old_balance: float,
        new_balance: float,
        transaction_id: str,
        reason: str
    ) -> None:
        """
        Log a balance change for a user.
        
        Args:
            user_id: ID of the user whose balance changed
            old_balance: Previous balance
            new_balance: New balance
            transaction_id: Associated transaction ID
            reason: Reason for the balance change
        """
        balance_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'user_id': user_id,
            'old_balance': old_balance,
            'new_balance': new_balance,
            'transaction_id': transaction_id,
            'reason': reason
        }
        
        AuditLogger._write_to_log(balance_entry, "BALANCE")
    
    @staticmethod
    def log_validation_failure(
        transaction_id: str,
        user_id: str,
        validation_type: str,
        error_message: str,
        context: Optional[Dict[str, Any]] = None
    ) -> None:
        """
        Log a validation failure during transaction processing.
        
        Args:
            transaction_id: ID of the failed transaction
            user_id: ID of the user involved
            validation_type: Type of validation that failed
            error_message: Description of the failure
            context: Optional additional context about the failure
        """
        failure_entry = {
            'timestamp': datetime.utcnow().isoformat(),
            'transaction_id': transaction_id,
            'user_id': user_id,
            'validation_type': validation_type,
            'error_message': error_message,
            'context': context or {}
        }
        
        AuditLogger._write_to_log(failure_entry, "VALIDATION_FAILURE") 