def callback_result(*, priority : Int32 = 1, &job)
  job.call
end

callback_result(priority: "high") { 9 }
