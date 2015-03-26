nagcheck
========

CGI providing on-demand service and host checking for Nagios via Mk LiveStatus

Specification
-------------

* Accepts requests for entities "host", "service" and "command" (e.g. {{GET https://<nagios>/nagcheck/service/node2.example.net/CPU}} or {{GET https://<nagios>/nagcheck/command/node2.example.net/check_cpu}})
* Allows requester to specify asynchronous or synchronous operation ({{?wait=true}}), default is true (synchronous)
* Allows requester to specify whether to report results to Nagios ({{?report=true}}), default is false
* Other parameters:
** {{check_timeout}} - seconds to wait (this is in addition to any timeout implemented by the check)
* Returns a JSON-serialized entity with the following attributes:
** *host_name:* The host to which the check is directed
** *address:* The address used for the host (from Nagios if the host exists, otherwise from DNS--can also be specified as a query string parameter)
** *service_description:* (optional) The service which was checked - Host checks and the results of commands do not have a service
** *check_command:* (optional) The name of the command object used to check the host or service (can also be specified as a query string parameter)
** *command_line:* The unexpanded command line executed (can also be specified as a query string parameter)
** *expanded_command_line:* The expandend command line - Only when {{?debug=true}} is specified
** *state:* The meaningful status exit code from the plugin or check command (0, 1, 2 or 3)
** *plugin_output:* The first line of the plugin or command output after stripping perfdata
** *perfdata:* The perfdata section (after the {{|}}-character in the plugin or command output)
** *long_plugin_output:* The unprocessed output of the plugin or check_command
** *check_time:* The time the command was executed

Query string parameters (*address*, *check_timeout*, *check_command*, *command_line*, *debug*, *report*, *wait) need to be explicitly permitted by including an *allow_params* key in the nagcheck configuration file. Typically *debug* output would be disabled, preventing the leaking of Nagios resource definitions (e.g. passwords); you may also desired to disable the *command_line* parameter, which allows the execution of arbitrary commands (though this is also available via wrapper plugins)

Features
--------

* You can't "report" the result of a command, only services and hosts
* Since you can't do that, only service and host checks can be checked asynchronously

Relevant Nagios Configuration Parameters
----------------------------------------

* Macro values (e.g. *$USER1$*, *service_check_timeout*)
* Host objects (for finding addresses and other macro values; host check command)
* Service objects (for finding service attributes and other macro values; service check commands)

Design
------

* Runs on Nagios server(s)
* Submits results through Nagios command file

HTTP Status Codes
-----------------

* 200 OK - Request was valid and synchronous, body contains result of check
* 202 Accepted - Request was valid and asynchronous, body is empty
* 400 Bad Request - Request was bad (for example, asynchronous, non-reporting execution)
* 404 Not Found - Request was not for a *host*, *service* or *command*
* 500 Internal Server Error - Request could not be completed due to errors on the server (e.g. Livestatus down)
