/*************************************************************************************************************
Script:             Data Clean Room - v5.5 - Provider Initialization
Create Date:        2022-02-09
Author:             J. Langseth, M. Rainey
Description:        Provider object and data initialization

Copyright © 2022 Snowflake Inc. All rights reserved
*************************************************************************************************************
SUMMARY OF CHANGES
Date(yyyy-mm-dd)    Author                              Comments
------------------- -------------------                 --------------------------------------------
2022-02-09          J. Langseth, M. Rainey              Initial Creation
2022-04-01          V. Malik                            v5.5 [Version without Native app , with JINJASQL
                                                        template & DP]
2022-04-13          M. Rainey                           Added SQL based templates & get_sql_js function.
2022-06-30          M. Rainey                           Updated get_sql_js params in support of multi-party.
                                                        Modified schema location for get_sql_js function so
                                                        funcction can be shared with Consumer.
2022-07-06          B. Klein                            Added new subscriptions data and included in share to
                                                        demo with multi-party.
2022-07-11          B. Klein                            Renamed _demo_ to _DCR_CLEANROOMPOC_  and added template_type to
                                                        templates to better support upgrades.
2022-07-12          B. Klein                            Updated get_sql_jinja to allow negative values.
2022-08-05          B. Klein                            Uncommented get_sql_jinja to facilitate DCR Assistant
2022-08-23          M. Rainey                           Remove differential privacy
2022-08-30          D. Cole, B. Klein                   Added new javascript jinja template engine
2022-10-24          B. Klein                            Separated framework code and demo data
2022-11-08          B. Klein                            Python GA
2023-02-02          B. Klein                            Added object comments for clarity
*************************************************************************************************************/


use role accountadmin;

create role if not exists data_clean_room_role;

// may need to drop and re-add warehouse if already created by accountadmin
//drop warehouse app_wh;

grant create share on account to role data_clean_room_role;
grant import share on account to role data_clean_room_role;
grant create database on account to role data_clean_room_role;
grant create warehouse on account to role data_clean_room_role;
grant execute task on account to role data_clean_room_role;
grant role data_clean_room_role to role sysadmin;
use role data_clean_room_role;

create warehouse if not exists app_wh;

//cleanup//
drop share if exists dcr_DCR_CLEANROOMPOC_app;

///////
/// CREATE MFB86782 DATA SCHEMAS
///////

// create database and schema for the app
create or replace database dcr_DCR_CLEANROOMPOC_provider_db;

// create schema for provider objects that app instances can securely utilize
create or replace schema dcr_DCR_CLEANROOMPOC_provider_db.shared_schema;

/////
// SETUP TEMPLATE PROCESSING
/////

use database dcr_DCR_CLEANROOMPOC_provider_db;
create or replace schema templates;
create or replace schema admin;
create schema dcr_DCR_CLEANROOMPOC_provider_db.cleanroom;

use schema dcr_DCR_CLEANROOMPOC_provider_db.templates;

// Python jinja function
create or replace function dcr_DCR_CLEANROOMPOC_provider_db.templates.get_sql_jinja(template string, parameters variant)
  returns string
  language python
  runtime_version = 3.8
  handler='apply_sql_template'
  packages = ('six','jinja2==3.0.3','markupsafe')
  comment='{"origin":"sf_ps_wls","name":"dcr","version":{"major":5, "minor":5},"attributes":{"component":"dcr",“role”:“provider”}}'
as
$$
# Most of the following code is copied from the jinjasql package, which is not included in Snowflake's python packages
from __future__ import unicode_literals
import jinja2
from six import string_types
from copy import deepcopy
import os
import re
from jinja2 import Environment
from jinja2 import Template
from jinja2.ext import Extension
from jinja2.lexer import Token
from markupsafe import Markup

try:
    from collections import OrderedDict
except ImportError:
    # For Python 2.6 and less
    from ordereddict import OrderedDict

from threading import local
from random import Random

_thread_local = local()

# This is mocked in unit tests for deterministic behaviour
random = Random()


class JinjaSqlException(Exception):
    pass

class MissingInClauseException(JinjaSqlException):
    pass

class InvalidBindParameterException(JinjaSqlException):
    pass

class SqlExtension(Extension):

    def extract_param_name(self, tokens):
        name = ""
        for token in tokens:
            if token.test("variable_begin"):
                continue
            elif token.test("name"):
                name += token.value
            elif token.test("dot"):
                name += token.value
            else:
                break
        if not name:
            name = "bind#0"
        return name

    def filter_stream(self, stream):
        """
        We convert
        {{ some.variable | filter1 | filter 2}}
            to
        {{ ( some.variable | filter1 | filter 2 ) | bind}}
        ... for all variable declarations in the template
        Note the extra ( and ). We want the | bind to apply to the entire value, not just the last value.
        The parentheses are mostly redundant, except in expressions like {{ '%' ~ myval ~ '%' }}
        This function is called by jinja2 immediately
        after the lexing stage, but before the parser is called.
        """
        while not stream.eos:
            token = next(stream)
            if token.test("variable_begin"):
                var_expr = []
                while not token.test("variable_end"):
                    var_expr.append(token)
                    token = next(stream)
                variable_end = token

                last_token = var_expr[-1]
                lineno = last_token.lineno
                # don't bind twice
                if (not last_token.test("name")
                    or not last_token.value in ('bind', 'inclause', 'sqlsafe')):
                    param_name = self.extract_param_name(var_expr)

                    var_expr.insert(1, Token(lineno, 'lparen', u'('))
                    var_expr.append(Token(lineno, 'rparen', u')'))
                    var_expr.append(Token(lineno, 'pipe', u'|'))
                    var_expr.append(Token(lineno, 'name', u'bind'))
                    var_expr.append(Token(lineno, 'lparen', u'('))
                    var_expr.append(Token(lineno, 'string', param_name))
                    var_expr.append(Token(lineno, 'rparen', u')'))

                var_expr.append(variable_end)
                for token in var_expr:
                    yield token
            else:
                yield token

def sql_safe(value):
    """Filter to mark the value of an expression as safe for inserting
    in a SQL statement"""
    return Markup(value)

def bind(value, name):
    """A filter that prints %s, and stores the value
    in an array, so that it can be bound using a prepared statement
    This filter is automatically applied to every {{variable}}
    during the lexing stage, so developers can't forget to bind
    """
    if isinstance(value, Markup):
        return value
    elif requires_in_clause(value):
        raise MissingInClauseException("""Got a list or tuple.
            Did you forget to apply '|inclause' to your query?""")
    else:
        return _bind_param(_thread_local.bind_params, name, value)

def bind_in_clause(value):
    values = list(value)
    results = []
    for v in values:
        results.append(_bind_param(_thread_local.bind_params, "inclause", v))

    clause = ",".join(results)
    clause = "(" + clause + ")"
    return clause

def _bind_param(already_bound, key, value):
    _thread_local.param_index += 1
    new_key = "%s_%s" % (key, _thread_local.param_index)
    already_bound[new_key] = value

    param_style = _thread_local.param_style
    if param_style == 'qmark':
        return "?"
    elif param_style == 'format':
        return "%s"
    elif param_style == 'numeric':
        return ":%s" % _thread_local.param_index
    elif param_style == 'named':
        return ":%s" % new_key
    elif param_style == 'pyformat':
        return "%%(%s)s" % new_key
    elif param_style == 'asyncpg':
        return "$%s" % _thread_local.param_index
    else:
        raise AssertionError("Invalid param_style - %s" % param_style)

def requires_in_clause(obj):
    return isinstance(obj, (list, tuple))

def is_dictionary(obj):
    return isinstance(obj, dict)

class JinjaSql(object):
    # See PEP-249 for definition
    # qmark "where name = ?"
    # numeric "where name = :1"
    # named "where name = :name"
    # format "where name = %s"
    # pyformat "where name = %(name)s"
    VALID_PARAM_STYLES = ('qmark', 'numeric', 'named', 'format', 'pyformat', 'asyncpg')
    def __init__(self, env=None, param_style='format'):
        self.env = env or Environment()
        self._prepare_environment()
        self.param_style = param_style

    def _prepare_environment(self):
        self.env.autoescape=True
        self.env.add_extension(SqlExtension)
        self.env.filters["bind"] = bind
        self.env.filters["sqlsafe"] = sql_safe
        self.env.filters["inclause"] = bind_in_clause

    def prepare_query(self, source, data):
        if isinstance(source, Template):
            template = source
        else:
            template = self.env.from_string(source)

        return self._prepare_query(template, data)

    def _prepare_query(self, template, data):
        try:
            _thread_local.bind_params = OrderedDict()
            _thread_local.param_style = self.param_style
            _thread_local.param_index = 0
            query = template.render(data)
            bind_params = _thread_local.bind_params
            if self.param_style in ('named', 'pyformat'):
                bind_params = dict(bind_params)
            elif self.param_style in ('qmark', 'numeric', 'format', 'asyncpg'):
                bind_params = list(bind_params.values())
            return query, bind_params
        finally:
            del _thread_local.bind_params
            del _thread_local.param_style
            del _thread_local.param_index

# Non-JinjaSql package code starts here
def quote_sql_string(value):
    '''
    If `value` is a string type, escapes single quotes in the string
    and returns the string enclosed in single quotes.
    '''
    if isinstance(value, string_types):
        new_value = str(value)
        new_value = new_value.replace("'", "''")
        #baseline sql injection deterrance
        new_value2 = re.sub(r"[^a-zA-Z0-9_.-]","",new_value)
        return "'{}'".format(new_value2)
    return value

def get_sql_from_template(query, bind_params):
    if not bind_params:
        return query
    params = deepcopy(bind_params)
    for key, val in params.items():
        params[key] = quote_sql_string(val)
    return query % params

def strip_blank_lines(text):
    '''
    Removes blank lines from the text, including those containing only spaces.
    https://stackoverflow.com/questions/1140958/whats-a-quick-one-liner-to-remove-empty-lines-from-a-python-string
    '''
    return os.linesep.join([s for s in text.splitlines() if s.strip()])

def apply_sql_template(template, parameters):
    '''
    Apply a JinjaSql template (string) substituting parameters (dict) and return
    the final SQL.
    '''
    j = JinjaSql(param_style='pyformat')
    query, bind_params = j.prepare_query(template, parameters)
    return strip_blank_lines(get_sql_from_template(query, bind_params))

$$;


//////
// CREATE MFB86782 ACCOUNT TABLE
//////

create or replace table dcr_DCR_CLEANROOMPOC_provider_db.cleanroom.provider_account(account_name varchar(1000)) comment='{"origin":"sf_ps_wls","name":"dcr","version":{"major":5, "minor":5},"attributes":{"component":"dcr",“role”:“provider”}}';

// do this for each consumer account
insert into dcr_DCR_CLEANROOMPOC_provider_db.cleanroom.provider_account (account_name)
select current_account();


//////
// CLEAN ROOM TEMPLATES
//////

// TODO CONFIRM THIS IS ALL SQL SAFE (partially done with identifier and string parsing in jinja renderer)

create or replace table dcr_DCR_CLEANROOMPOC_provider_db.templates.dcr_templates (party_account varchar(1000) ,template_name string, template string, dp_sensitivity int, dimensions varchar(2000), template_type string) comment='{"origin":"sf_ps_wls","name":"dcr","version":{"major":5, "minor":5},"attributes":{"component":"dcr",“role”:“provider”}}';

// create a view to allow each consumer account to see their templates
create or replace secure view dcr_DCR_CLEANROOMPOC_provider_db.cleanroom.templates comment='{"origin":"sf_ps_wls","name":"dcr","version":{"major":5, "minor":5},"attributes":{"component":"dcr",“role”:“provider”}}' as
select * from dcr_DCR_CLEANROOMPOC_provider_db.templates.dcr_templates  where current_account() = party_account;


//////////
// CREATE CLEAN ROOM UTILITY FUNCTIONS
//////////

// create a request tracking table that will also contain allowed statements
create or replace table dcr_DCR_CLEANROOMPOC_provider_db.admin.request_log
    (party_account varchar(1000), request_id varchar(1000), request_ts timestamp, request variant, query_hash varchar(1000),
     template_name varchar(1000), epsilon double, sensitivity int,  app_instance_id varchar(1000), processed_ts timestamp, approved boolean, error varchar(1000))
     comment='{"origin":"sf_ps_wls","name":"dcr","version":{"major":5, "minor":5},"attributes":{"component":"dcr",“role”:“provider”}}';

// create a dynamic secure view to allow each consumer to only see the status of their request rows
create or replace secure view dcr_DCR_CLEANROOMPOC_provider_db.cleanroom.provider_log comment='{"origin":"sf_ps_wls","name":"dcr","version":{"major":5, "minor":5},"attributes":{"component":"dcr",“role”:“provider”}}' as
select * from dcr_DCR_CLEANROOMPOC_provider_db.admin.request_log where current_account() = party_account;


//////////////////
// ADD DATA FIREWALL ROW ACCESS POLICY
//////////////////

create or replace row access policy dcr_DCR_CLEANROOMPOC_provider_db.shared_schema.data_firewall as (foo varchar) returns boolean ->
    exists  (select request_id from dcr_DCR_CLEANROOMPOC_provider_db.admin.request_log w
               where party_account=current_account()
                  and approved=true
                  and query_hash=sha2(current_statement()));

//see request log
select * from dcr_DCR_CLEANROOMPOC_provider_db.admin.request_log;


//////
// SHARE CLEANROOM
//////

// create application share : Updated using normal share without native app
create or replace share dcr_DCR_CLEANROOMPOC_app ;

// make required grants
grant usage on database dcr_DCR_CLEANROOMPOC_provider_db to share dcr_DCR_CLEANROOMPOC_app;
grant usage on schema dcr_DCR_CLEANROOMPOC_provider_db.cleanroom to share dcr_DCR_CLEANROOMPOC_app;
grant select on dcr_DCR_CLEANROOMPOC_provider_db.cleanroom.provider_log to share dcr_DCR_CLEANROOMPOC_app;
grant select on dcr_DCR_CLEANROOMPOC_provider_db.cleanroom.provider_account to share dcr_DCR_CLEANROOMPOC_app;
grant select on dcr_DCR_CLEANROOMPOC_provider_db.cleanroom.templates to share dcr_DCR_CLEANROOMPOC_app;
alter share dcr_DCR_CLEANROOMPOC_app add accounts = XOB00824;
