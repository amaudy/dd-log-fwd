import json
import os
import gzip
import base64
from dataclasses import dataclass
from typing import Any, Dict, List, Optional
import urllib.request
import urllib.error
from http.client import HTTPResponse
import logging

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

@dataclass
class DatadogLog:
    ddsource: str
    ddtags: str
    hostname: str
    message: str
    service: str

def forward_to_datadog(logs: List[Dict[str, Any]], api_key: str, timeout: int = 10) -> Optional[HTTPResponse]:
    """
    Forward logs to Datadog HTTP API with improved error handling and timeout
    
    Args:
        logs: List of log entries to send
        api_key: Datadog API key
        timeout: Request timeout in seconds
    
    Returns:
        HTTPResponse object if successful, None if failed
    
    Raises:
        ValueError: If logs exceed maximum batch size
        RuntimeError: If Datadog API request fails
    """
    MAX_BATCH_SIZE = 1000  # Define reasonable batch size limit
    
    if len(logs) > MAX_BATCH_SIZE:
        raise ValueError(f"Log batch size {len(logs)} exceeds maximum of {MAX_BATCH_SIZE}")
        
    url = "https://http-intake.logs.datadoghq.com/api/v2/logs"
    headers = {
        "Content-Type": "application/json",
        "DD-API-KEY": api_key
    }

    data = json.dumps(logs).encode('utf-8')
    req = urllib.request.Request(url, data=data, headers=headers, method='POST')
    
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.read()
    except urllib.error.HTTPError as e:
        logger.error(f"HTTP error sending logs to Datadog: {e.code} - {e.reason}")
        raise RuntimeError(f"Failed to send logs to Datadog: {e.reason}")
    except urllib.error.URLError as e:
        logger.error(f"Network error sending logs to Datadog: {str(e)}")
        raise RuntimeError(f"Network error sending logs to Datadog: {str(e)}")
    except Exception as e:
        logger.error(f"Unexpected error sending logs to Datadog: {str(e)}")
        raise

def process_cloudwatch_logs(event: Dict[str, Any], context: Any) -> Dict[str, str]:
    """Process CloudWatch Logs and forward to Datadog"""
    try:
        # Get API key with fallback
        api_key = os.environ.get("DD_API_KEY")
        if not api_key:
            raise ValueError("DD_API_KEY environment variable not set")

        # Decode and uncompress CloudWatch Logs data
        compressed_payload = base64.b64decode(event['awslogs']['data'])
        uncompressed_payload = gzip.decompress(compressed_payload)
        log_events = json.loads(uncompressed_payload)

        # Transform logs to Datadog format
        dd_logs = []
        for event in log_events['logEvents']:
            log = DatadogLog(
                ddsource="cloudwatch",
                ddtags=os.environ.get("DD_TAGS", ""),
                hostname=log_events['logGroup'],
                message=event['message'],
                service="flask-echo"
            )
            dd_logs.append(log.__dict__)

        # Forward logs to Datadog
        forward_to_datadog(dd_logs, api_key)

        return {
            "statusCode": 200,
            "body": json.dumps({
                "message": "Logs forwarded successfully",
                "count": len(dd_logs)
            })
        }
    except ValueError as e:
        logger.error(f"Configuration error: {str(e)}")
        raise
    except Exception as e:
        logger.error(f"Error processing logs: {str(e)}")
        raise

def lambda_handler(event: Dict[str, Any], context: Any) -> Dict[str, str]:
    """Lambda handler function"""
    try:
        return process_cloudwatch_logs(event, context)
    except Exception as e:
        print(f"Error processing logs: {str(e)}")
        raise 