#!/usr/bin/env Rscript
library(DBI)
library(odbc)

# Parse command line arguments
args = commandArgs(trailingOnly=TRUE)
if (length(args)!=4) {
  stop("Exactly four arguments are required: db_type, db_name, port and server_name")
}
db_type = args[1]
db_name = args[2]
port = args[3]
server_name = args[4]

# Connect to the database
print(paste("Attempting to connect to '", db_name, "' on '", server_name, "' via port '", port, sep=""))
if (db_type == "mssql") {
    cnxn <- DBI::dbConnect(
        odbc::odbc(),
        Driver = "ODBC Driver 17 for SQL Server",
        Server = paste(server_name, port, sep=","),
        Database = db_name,
        Trusted_Connection = "yes"
    )
} else if (db_type == "postgres") {
    cnxn <- DBI::dbConnect(
        RPostgres::Postgres(),
        host = server_name,
        port = port,
        dbname = db_name
    )
}

# Run a query and save the output into a dataframe
df <- dbGetQuery(cnxn, "SELECT * FROM information_schema.tables;")
if (dim(df)[1] > 0) {
    print(head(df, 5))
    print("All database tests passed")
}
