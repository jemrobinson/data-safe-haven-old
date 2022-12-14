#! /usr/bin/env python
import argparse
import psycopg2
import pyodbc
import pandas as pd


def test_database(server_name, port, db_type, db_name):
    print(f"Attempting to connect to '{db_name}' on '{server_name}' via port {port}")
    if db_type == "mssql":
        cnxn = pyodbc.connect(
            f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server_name},{port};DATABASE={db_name};Trusted_Connection=yes;"
        )
    elif db_type == "postgres":
        cnxn = psycopg2.connect(host=server_name, port=port, database=db_name)
    df = pd.read_sql("SELECT * FROM information_schema.tables;", cnxn)
    if df.size:
        print(df.head(5))
        print("All database tests passed")


# Parse command line arguments
parser = argparse.ArgumentParser()
parser.add_argument(
    "-d",
    "--db-type",
    type=str,
    choices=["mssql", "postgres"],
    help="Which database type to use",
)
parser.add_argument("-n", "--db-name", type=str, help="Which database to connect to")
parser.add_argument("-p", "--port", type=str, help="Which port to connect to")
parser.add_argument("-s", "--server-name", type=str, help="Which server to connect to")
args = parser.parse_args()

# Run database test
test_database(args.server_name, args.port, args.db_type, args.db_name)
