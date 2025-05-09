# Signals

KFS implements standard **POSIX** signals. Signals cannot be queued but 
while a signal is executing another can arrive and and steal it's execution time
if the the currently executing signal is not blocking it.

KFS implements the following flags for sigaction

* **SA_NODEFER**   Do not add the signal to the thread's signal mask while the
                handler is executing, unless the signal is specified in
                act.sa_mask
* **SA_RESETHAND**   Resets the handler of the signal to default when execution of that handler starts.
