require "../src/stdlib/lib_c/aarch64-darwin/c/sys/types"

lib LibC
  fun pthread_cond_init(x0 : PthreadCondT*, x1 : PthreadCondattrT*) : Int
  fun pthread_cond_timedwait_relative_np(x0 : PthreadCondT*, x1 : PthreadMutexT*, x2 : Timespec*) : Int
end
