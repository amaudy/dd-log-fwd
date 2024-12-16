from fastapi import FastAPI, HTTPException, status
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
import logging

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

@app.get("/health")
async def health_check():
    logger.info("Health check endpoint called")
    return {"status": "healthy"}

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

# Error handler for uncaught exceptions
@app.exception_handler(Exception)
async def global_exception_handler(request, exc):
    logger.error(f"Unhandled exception: {str(exc)}")
    return {"detail": "Internal Server Error"}

@app.get("/")
def read_root():
    return {"Hello": "World"}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=5000)