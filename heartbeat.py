import zmq
from IPython.zmq.heartbeat import Heartbeat
from IPython.utils.localinterfaces import LOCALHOST

context = zmq.Context()

beat = Heartbeat(context, (LOCALHOST, 5554))
beat.start()

raw_input("input anything and hit return to stop the heart beating\n");
