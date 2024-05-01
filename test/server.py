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
import argparse
import ssl

from OpenSSL import crypto

def cert_gen(
    emailAddress="emailAddress",
    commonName="commonName",
    countryName="NT",
    localityName="localityName",
    stateOrProvinceName="stateOrProvinceName",
    organizationName="organizationName",
    organizationUnitName="organizationUnitName",
    serialNumber=0,
    validityStartInSeconds=0,
    validityEndInSeconds=10*365*24*60*60,
    KEY_FILE = "key.pem",
    CERT_FILE="cert.pem"):
    #can look at generated file using openssl:
    #openssl x509 -inform pem -in selfsigned.crt -noout -text
    # create a key pair
    k = crypto.PKey()
    k.generate_key(crypto.TYPE_RSA, 4096)
    # create a self-signed cert
    cert = crypto.X509()
    cert.get_subject().C = countryName
    cert.get_subject().ST = stateOrProvinceName
    cert.get_subject().L = localityName
    cert.get_subject().O = organizationName
    cert.get_subject().OU = organizationUnitName
    cert.get_subject().CN = commonName
    cert.get_subject().emailAddress = emailAddress
    cert.set_serial_number(serialNumber)
    cert.gmtime_adj_notBefore(0)
    cert.gmtime_adj_notAfter(validityEndInSeconds)
    cert.set_issuer(cert.get_subject())
    cert.set_pubkey(k)
    cert.sign(k, 'sha512')
    with open(CERT_FILE, "wt") as f:
        f.write(crypto.dump_certificate(crypto.FILETYPE_PEM, cert).decode("utf-8"))
    with open(KEY_FILE, "wt") as f:
        f.write(crypto.dump_privatekey(crypto.FILETYPE_PEM, k).decode("utf-8"))


# This is a simple implementation of the Piwigo protocol to run locally
# for testing publishing in offline-situations

class SimpleRequestHandler(http.server.BaseHTTPRequestHandler):
    _REPLY_TEMPLATE = b'<?xml version="1.0"?><rsp stat="ok">%s</rsp>'

    def reply_ok(self, content=b''):
        self.send_response(200)
        self.send_header('Content-type', 'text/xml')
        self.send_header('Set-Cookie', 'pwg_id="12345"')
        self.end_headers()
        self.wfile.write(SimpleRequestHandler._REPLY_TEMPLATE % content)

    def do_POST(self):
        self.log_message("Got POST request for path " + self.path)
        ctype, pdict = cgi.parse_header(self.headers['content-type'])
        self.log_message("Content-Type = " + ctype)
        if ctype == 'multipart/form-data':
            pdict['boundary'] = bytes(pdict['boundary'], 'utf-8')
            pdict['CONTENT-LENGTH'] = self.headers['Content-Length']
            postvars = cgi.parse_multipart(self.rfile, pdict)
        elif ctype == 'application/x-www-form-urlencoded':
            length = int(self.headers['content-length'])
            postvars = urllib.parse.parse_qs(self.rfile.read(length),
                                             keep_blank_values=1)
        else:
            postvars = {}

        try:
            method = postvars[b'method'][0]
        except KeyError:
            method = postvars['method'][0]

        # Make sure we have a utf8 string
        try:
            method = method.decode()
        except AttributeError:
            # Already was a string "has no attribute 'decode'"
            pass

        self.log_message("Received method call for " + str(method))
        time.sleep(1)

        if self.path != '/ws.php':
            self.log_error(f'Unknown page: {self.path}')
            self.send_response(404)
            return


        if method == 'pwg.session.login':
            self.reply_ok()
            return
        elif method == 'pwg.session.getStatus':
            self.reply_ok(b'<username>SomeRandomDude</username>')
            return
        elif method == 'pwg.categories.getList':
            self.reply_ok(b'<categories></categories>')
            return
        elif method == 'pwg.categories.add':
            self.reply_ok(b'<id>765</id>')
            return
        elif method == 'pwg.images.addSimple':
            self.reply_ok(b'<image_id>2387</image_id>')
            return
        elif method == 'pwg.images.rate':
            self.reply_ok(b'<image_id>2387</image_id>')
            return
        else:
            self.log_error('Unknown method {0}'.format(method))

        self.send_response(500)

def run(port=8080, do_ssl=False):
    server_address = ('127.0.0.1', port)
    httpd = http.server.HTTPServer(server_address, SimpleRequestHandler)
    if do_ssl:
        cert_gen()
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain("cert.pem", "key.pem")
        httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

    httpd.serve_forever()

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description = "Piwigo test server")
    parser.add_argument('--port', type=int, default=8080)
    parser.add_argument('--ssl', action='store_true')
    args = parser.parse_args()

    run(port=args.port, do_ssl = args.ssl)
