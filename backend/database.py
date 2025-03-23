import sqlite3
from sqlite3 import Error

def create_connection():
    """Create a database connection to sample.db"""
    conn = None
    try:
        conn = sqlite3.connect('sample.db')
        print("Successfully connected to SQLite database")
        return conn
    except Error as e:
        print(f"Error connecting to database: {e}")
        return None

def init_db():
    """Initialize the database connection test"""
    conn = create_connection()
    if conn is not None:
        print("Database connection test successful")
        conn.close()
    else:
        print("Error: Could not establish database connection")

if __name__ == '__main__':
    init_db()