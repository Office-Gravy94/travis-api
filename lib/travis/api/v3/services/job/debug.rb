module Travis::API::V3
  class Services::Job::Debug < Service
    params "quiet"

    attr_reader :job

    def run
      raise LoginRequired unless access_control.logged_in? or access_control.full_access?
      raise NotFound      unless @job = find(:job)
      raise WrongCredentials unless Travis.config.debug_tools_enabled or Travis::Features.active?(:debug_tools, access_control.user)
      access_control.permissions(job).debug!

      job.config.merge! debug_data
      job.save!

      query.restart(access_control.user)
      accepted(job: job, state_change: :created)
    end

    def debug_data
      {
        debug: {
          stage: 'before_install',
          previous_state: job.state,
          created_by: access_control.user.login,
          quiet: params["quiet"] || false
        }
      }
    end
  end
end