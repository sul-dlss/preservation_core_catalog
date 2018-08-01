# The default Socket.getbyhostname and other libc-bound DNS resolutions in Ruby block the entire VM until they complete.
# In a single thread this doesn't matter, but it can cause competition and deadlock in multi-threaded environments.
# This library is included as part of Ruby to swap out the libc implementation for a thread-friendly pure ruby version.
# It is a monkey-patch, but obviously one provided and supported by the Ruby maintainers themselves.
require 'resolv-replace'
