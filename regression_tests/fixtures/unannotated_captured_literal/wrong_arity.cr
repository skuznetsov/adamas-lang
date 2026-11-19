def callback_result(&job)
  job.call
end

callback_result { |extra| extra }
