import os
import io
import sys
from dotenv import load_dotenv
from snowflake.snowpark import Session
from snowflake.snowpark.functions import col
load_dotenv()
connection_parameters = {
                                "account": os.getenv('account'),
                                "user": os.getenv('user'),
                                "password": os.getenv('password'),
                                "role": os.getenv('role'), 
                                "warehouse": os.getenv('warehouse'),
                                "database": os.getenv('database'),
                                "schema": os.getenv('schema')
                            }

new_session = Session.builder.configs(connection_parameters).create()
tableName = 'DB_PLAYGROUND.PUBLIC.TBL_SAMPLE'
dataframe = new_session.table(tableName).filter(col("EMPLOYEES") > 800)
dataframe.show()