from fastapi import FastAPI, HTTPException, status, Response
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
import logging
from ddtrace import patch_all
from typing import Dict
from fastapi.responses import JSONResponse

# Initialize tracing before other imports
patch_all()

# Initialize FastAPI app
app = FastAPI()

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)

# Mock database connection
DB_URL = "sqlite:///./test.db"
engine = create_engine(DB_URL)

# Define status code mappings
STATUS_CODES: Dict[int, str] = {
    200: "OK",
    201: "Created",
    204: "No Content",
    301: "Moved Permanently",
    302: "Found",
    304: "Not Modified",
    400: "Bad Request",
    401: "Unauthorized",
    403: "Forbidden",
    404: "Not Found",
    405: "Method Not Allowed",
    408: "Request Timeout",
    409: "Conflict",
    429: "Too Many Requests",
    500: "Internal Server Error",
    501: "Not Implemented",
    502: "Bad Gateway",
    503: "Service Unavailable",
    504: "Gateway Timeout"
}

@app.get("/{code}")
async def get_status_code(code: int):
    """Return specific status code with its description"""
    if code not in STATUS_CODES:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid status code: {code}"
        )
    
    return Response(
        content=f"Status Code: {code}\nDetail: {STATUS_CODES[code]}",
        status_code=code,
        media_type="text/plain"
    )

@app.get("/health")
async def health_check():
    """
    Simple health check endpoint that returns 200 OK
    """
    return JSONResponse(
        status_code=status.HTTP_200_OK,
        content={"status": "healthy"}
    )

@app.get("/error-500")
async def error_500():
    logger.error("Internal Server Error occurred")
    raise HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail="Internal Server Error"
    )

@app.get("/error-403")
async def error_403():
    logger.error("Forbidden access attempted")
    raise HTTPException(
        status_code=status.HTTP_403_FORBIDDEN,
        detail="Forbidden access"
    )

@app.get("/error-database-query")
async def error_database_query():
    try:
        # Intentionally causing a database error
        with engine.connect() as connection:
            # Try to query a non-existent table
            connection.execute(text("SELECT * FROM non_existent_table"))
    except SQLAlchemyError as e:
        logger.error(f"Database error occurred: {str(e)}")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Database error: {str(e)}"
        )

@app.get("/")
def read_root():
    return {"Hello": "World"}

# Error handler for uncaught exceptions
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Unhandled exception: {str(exc)}")
    return {"detail": "Internal Server Error"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)