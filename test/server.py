#!/usr/bin/env python3
#
# Copyright 2017 Jens Georg <mail@jensge.org>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy of
# this software and associated documentation files (the "Software"), to deal in
# the Software without restriction, including without limitation the rights to
# use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
# of the Software, and to permit persons to whom the Software is furnished to do
# so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#

import http.server
import cgi
import urllib.parse
import time

# This is a simple implementation of the Piwigo protocol to run locally
# for testing publishing in offline-situations

class SimpleRequestHandler(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.log_message("Got POST request for path " + self.path)
        ctype, pdict = cgi.parse_header(self.headers['content-type'])
        self.log_message("Content-Type = " + ctype)
        if ctype == 'multipart/form-data':
            pdict['boundary'] = bytes(pdict['boundary'], 'utf-8')
            postvars = cgi.parse_multipart(self.rfile, pdict)
        elif ctype == 'application/x-www-form-urlencoded':
            length = int(self.headers['content-length'])
            postvars = urllib.parse.parse_qs(self.rfile.read(length),
                                             keep_blank_values=1)
        else:
            postvars = {}

        try:
            method = postvars[b'method'][0]
        except:
            method = postvars['method'][0]

        self.log_message("Received method call for " + str(method))
        time.sleep(1)

        if self.path == '/ws.php':
            try:

                if method == b'pwg.session.login':
                    self.send_response(200)
                    self.send_header('Content-type', 'text/xml')
                    self.send_header('Set-Cookie', 'pwg_id="12345"')
                    self.end_headers()
                    self.wfile.write(b'<?xml version="1.0"?><piwigo stat="ok"></piwigo>')
                    return
                elif method == b'pwg.session.getStatus':
                    self.send_response(200)
                    self.send_header('Content-type', 'text/xml')
                    self.send_header('Set-Cookie', 'pwg_id="12345"')
                    self.end_headers()
                    self.wfile.write(b'<?xml version="1.0"?><piwigo stat="ok"><username>test</username></piwigo>')
                    return
                elif method == b'pwg.categories.getList':
                    self.send_response(200)
                    self.send_header('Content-type', 'text/xml')
                    self.send_header('Set-Cookie', 'pwg_id="12345"')
                    self.end_headers()
                    self.wfile.write(b'<?xml version="1.0"?><piwigo stat="ok"><categories></categories></piwigo>')
                    return
                elif method == b'pwg.categories.add':
                    self.send_response(200)
                    self.send_header('Set-Cookie', 'pwg_id="12345"')
                    self.end_headers()
                    self.wfile.write(b'<?xml version="1.0"?><piwigo stat="ok"><id>765</id></piwigo>')
                    return
                elif method == b'pwg.images.addSimple':
                    self.send_response(200)
                    self.send_header('Set-Cookie', 'pwg_id="12345"')
                    self.end_headers()
                    self.wfile.write(b'<?xml version="1.0"?><piwigo stat="ok"></piwigo>')
                    return
            except:
                self.log_error('Unknown method {0}'.format(postvars[b'method']))
                pass

        self.send_response(500)

def run(server_class = http.server.HTTPServer, handler_class = SimpleRequestHandler):
    server_address = ('127.0.0.1', 8080)
    httpd = server_class(server_address, handler_class)
    httpd.serve_forever()

run()
