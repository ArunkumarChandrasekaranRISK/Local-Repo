from snowflake.snowpark import Session
from snowflake.snowpark.functions import col

connection_parameters = {
    "account": "ag08457.east-us-2.azure",
    "user": "CHANDRASEKARANA1",
    "password": "Psg@04p606",
    "role": "SYSADMIN",  # optional
    "warehouse": "XHRPLAYGROUND",  # optional
    "database": "DB_PLAYGROUND",  # optional
    "schema": "PUBLIC",  # optional
  }  

new_session = Session.builder.configs(connection_parameters).create()
tableName = 'DB_PLAYGROUND.PUBLIC.TBL_SAMPLE'
dataframe = new_session.table(tableName).filter(col("EMPLOYEES") > 100)
dataframe.show()