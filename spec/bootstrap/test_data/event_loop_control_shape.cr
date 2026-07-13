lib LibC
  fun printf(format : UInt8*, ...) : Int32
end

{% if flag?(:wasi) %}
  require "./event_loop_control_wasi"
{% elsif flag?(:unix) %}
  {% if flag?("evloop=libevent") %}
    require "./event_loop_control_libevent"
  {% elsif flag?("evloop=epoll") %}
    require "./event_loop_control_epoll"
  {% elsif flag?("evloop=kqueue") || flag?(:darwin) %}
    require "./event_loop_control_kqueue"
  {% end %}
{% end %}

LibC.printf("ADAMAS_EVENT_LOOP_CONTROL:%d\n", EventLoopControl::VALUE)
