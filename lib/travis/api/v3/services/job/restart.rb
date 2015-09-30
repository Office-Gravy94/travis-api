module Travis::API::V3
  class Services::Job::Restart < Service

    def run
      raise LoginRequired unless access_control.logged_in? or access_control.full_access?
      raise NotFound      unless job = find(:job)
      access_control.permissions(job).restart!

      query.restart(access_control.user)
      accepted(job: job, state_change: :restart)
    end
  end
end
