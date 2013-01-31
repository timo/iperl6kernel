import zmq
import uuid
import hmac

from datetime import datetime
from subprocess import Popen, PIPE

import json

from zmq.utils import jsonapi

from IPython.utils.jsonutil import extract_dates, date_default
from IPython.utils.localinterfaces import LOCALHOST
from IPython.zmq.heartbeat import Heartbeat

json_packer = lambda obj: jsonapi.dumps(obj, default=date_default)
json_unpacker = lambda s: extract_dates(jsonapi.loads(s))

pack = json_packer
unpack = json_unpacker

#DELIM = "<IDS|MSG>"
#my_ident = str(uuid.uuid4())
#my_session = str(uuid.uuid4())

#hmac_key = "e8da7b2b-75a6-46d9-902e-ebd13b3c98f2"
my_username = "camilla"

#HMAC_O = hmac.HMAC(hmac_key)
#def sign(messages):
    #h = HMAC_O.copy()
    #for msg in messages:
        #h.update(msg)
    #return h.hexdigest()

#my_metadata = {
        #'dependencies_met' : True,
        #'engine' : my_ident,
        #'started' : datetime.now(),
    #}


#rakudo = Popen("perl6", stdin=PIPE, stdout=PIPE)
#if rakudo.stdout.read(2) != "> ":
    #print "ERROR!"
#rakudo_counter = [0]

context = zmq.Context()
stdin_sock = context.socket(zmq.ROUTER)
stdin_sock.bind("tcp://*:5551")

shell_sock = context.socket(zmq.ROUTER)
shell_sock.bind("tcp://*:5552")

iopub= context.socket(zmq.PUB)
iopub.bind("tcp://*:5553")

beat = Heartbeat(context, (LOCALHOST, 5554))
beat.start()

poller = zmq.Poller()
poller.register(stdin_sock, zmq.POLLIN)
poller.register(shell_sock, zmq.POLLIN)

#def msg_header(msg_id, msg_type):
    #username = my_username
    #session = my_session
    #date = datetime.now()
    #return locals()

#def send_answer(to_ident, parent_header, header, content):
    #parent_header = pack(parent_header)
    #header = pack(header)
    #content = pack(content)
    #signature = sign([header, parent_header, content])
    #shell_sock.send(to_ident, zmq.SNDMORE)
    #shell_sock.send(DELIM, zmq.SNDMORE)
    #shell_sock.send(signature, zmq.SNDMORE)
    #shell_sock.send(header, zmq.SNDMORE)
    #shell_sock.send(parent_header, zmq.SNDMORE)
    #shell_sock.send(content)

    #print "publishing answer:"
    #print parent_header
    #print header
    #print content

#def publish(msg_type, topic, content, parent_header):
    #parent_header = pack(parent_header)
    #header = pack(msg_header(str(uuid.uuid4()), msg_type))
    #content = pack(content)
    #signature = sign([header, parent_header, content])
    #iopub.send("kernel.%s.%s" % (my_ident, topic), zmq.SNDMORE)
    #iopub.send(DELIM, zmq.SNDMORE)
    #iopub.send(signature, zmq.SNDMORE)
    #iopub.send(header, zmq.SNDMORE)
    #iopub.send(parent_header, zmq.SNDMORE)
    #iopub.send(content)

#def handle_shell_sock_message(messages):
    #delimpos = messages.index(DELIM)
    #idents = messages[:delimpos]
    #hmac = messages[delimpos+1]
    #header = unpack(messages[delimpos+2])
    #parent_header = unpack(messages[delimpos+3])
    #content = unpack(messages[delimpos+4])
    #streams = messages[delimpos+5:]

    #msg_type = header["msg_type"]
    #msg_id = header["msg_id"]

    #print(" ".join(idents) + " sent a " + header["msg_type"])
    #print header
    #print content

    #if globals().get("handle_" + msg_type, None) is not None:
        #globals()["handle_"+msg_type](idents[0], header, content, streams)

#def handle_execute_request(to_ident, header, content, streams):
    #print "handling execute request"
    
    #silent = content["silent"]

    #if not silent:
        #rakudo_counter[0] += 1

    #if not content["code"].endswith("\n"):
        #content["code"] += "\n"

    #rakudo.stdin.write(content["code"])
    #newlines = content["code"].count("\n")
    #while True:
        #read = rakudo.stdout.read(1)
        #if read == "\n":
            #newlines -= 1
            #if newlines == 0:
                #break

    #if not silent:
        #publish("pyin", "pyin",
                #{"execution_count": rakudo_counter[0],
                 #"code": content["code"]},
                #header)

    #result = ""
    #while True:
        #read = rakudo.stdout.read(1)
        #if result.endswith("\n>") and read == " ":
            #result = result[:-2]
            #break
        #else:
            #result += read
    #print repr(result), " <- execution result"
    #new_header = msg_header(str(uuid.uuid4()), "execute_reply")
    #content = {
        #"status": "OK",
        #"execution_count": rakudo_counter[0],
        #"payload": []
    #}
    #send_answer(to_ident, header, new_header, content)

    #if not silent:
        #publish("pyout", "pyout",
                #{"execution_count": rakudo_counter[0],
                 #"data": {
                     #"text/plain": result,
                     #}
                #},
                #header)

def handle_shell_sock_message(parts):
    data = json.dumps(["shellsock"]+parts)
    datlen = len(data) + 1
    print datlen
    print data

shell_messages = []
stdin_messages = []
while True:
    socks = dict(poller.poll())

    if socks.get(shell_sock) == zmq.POLLIN:
        message = shell_sock.recv()
        more = shell_sock.getsockopt(zmq.RCVMORE)
        shell_messages.append(message)
        if not more:
            handle_shell_sock_message(shell_messages)
            shell_messages = []

    if socks.get(stdin_sock) == zmq.POLLIN:
        message = stdin_sock.recv()
        print("stdin socket received:")
        print(repr(message))
        print()
