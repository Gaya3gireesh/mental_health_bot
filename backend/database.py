import sqlite3
from sqlite3 import Error
import hashlib
import os

def create_connection():
    """Create a database connection to the database in the root folder"""
    # Use the database in the root directory instead of backend
    root_dir = os.path.dirname(os.path.dirname(__file__))  # Go up one level to the project root
    db_path = os.path.join(root_dir, 'sample.db')
    conn = None
    try:
        conn = sqlite3.connect(db_path)
        print(f"Successfully connected to SQLite database at {db_path}")
        return conn
    except Error as e:
        print(f"Error connecting to database: {e}")
        return None

def init_db():
    """Initialize the database with necessary tables"""
    conn = create_connection()
    if conn is not None:
        try:
            # Check if the table exists
            cursor = conn.cursor()
            cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users'")
            table_exists = cursor.fetchone()
            
            if not table_exists:
                # Create users table if it doesn't exist
                users_table = """ CREATE TABLE IF NOT EXISTS users (
                                id INTEGER PRIMARY KEY AUTOINCREMENT,
                                email TEXT UNIQUE NOT NULL,
                                password TEXT NOT NULL,
                                name TEXT NOT NULL,
                                mood TEXT
                            ); """
                
                cursor.execute(users_table)
                conn.commit()
                print("Created users table")
            else:
                print("Users table already exists")
                
            conn.close()
            return True
        except Error as e:
            print(f"Error initializing database: {e}")
            return False
    else:
        print("Error: Could not establish database connection")
        return False

def create_user(email, password, name, mood=None):
    """Create a new user in the database"""
    # First ensure the database and table exist
    init_db()
    
    conn = create_connection()
    if conn is not None:
        try:
            # Hash the password
            hashed_password = hashlib.sha256(password.encode()).hexdigest()
            
            # Insert user data
            sql = ''' INSERT INTO users(email, password, name, mood)
                      VALUES(?,?,?,?) '''
            cur = conn.cursor()
            cur.execute(sql, (email, hashed_password, name, mood))
            conn.commit()
            user_id = cur.lastrowid
            print(f"Created new user with ID: {user_id}, name: {name}, email: {email}")
            conn.close()
            return {"success": True, "user_id": user_id}
        except sqlite3.IntegrityError as e:
            print(f"Database integrity error: {e}")
            conn.close()
            return {"success": False, "error": "Email already exists"}
        except Error as e:
            print(f"Error creating user: {e}")
            conn.close()
            return {"success": False, "error": str(e)}
    else:
        return {"success": False, "error": "Database connection failed"}

def get_user_by_email(email):
    """Get user data by email"""
    conn = create_connection()
    if conn is not None:
        try:
            cur = conn.cursor()
            cur.execute("SELECT id, email, password, name, mood FROM users WHERE email = ?", (email,))
            row = cur.fetchone()
            conn.close()
            
            if row:
                return {
                    "id": row[0],
                    "email": row[1],
                    "password": row[2],
                    "name": row[3],
                    "mood": row[4]
                }
            else:
                return None
        except Error as e:
            print(f"Error getting user: {e}")
            conn.close()
            return None
    else:
        return None

# Initialize the DB when the module is imported
init_db()

if __name__ == '__main__':
    # Test the database connection
    print("Testing database connection...")
    success = init_db()
    print(f"Database initialization {'successful' if success else 'failed'}")

    # Testing user creation
    print("\nTesting user creation...")
    test_user = create_user("test@example.com", "password123", "Test User")
    print(f"User creation result: {test_user}")
    
    # Testing user retrieval
    print("\nTesting user retrieval...")
    user = get_user_by_email("test@example.com")
    print(f"User retrieval result: {user}")