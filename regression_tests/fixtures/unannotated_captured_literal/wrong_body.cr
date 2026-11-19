def callback_result(&job)
  job.call
end

callback_result { unknown_callback_operation }
