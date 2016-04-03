class Cms::Deployment < Cms::Base
  self.prefix      = "#{Settings.cms_path_prefix}/dj/simple/"
  self.primary_key = :deploymentId

  # Overwritten to fix "pausing" state if necessary.
  def self.find_single(*args)
    check_pausing_state(super)
  end

  def self.build(attributes = {})
    self.new(ActiveSupport::HashWithIndifferentAccess.new({:releaseId       => '',
                                                           :nsPath          => '',
                                                           :deploymentState => ''}).merge(attributes))
  end

  def self.find_open_or_build(options = {})
    latest = Cms::Deployment.all( :params => { :latest => "true" }.merge(options) ).first
    if latest.nil?
      return Cms::Deployment.build(:releaseId => options[:releaseId])
    else
      if (latest.deploymentState == 'active' || latest.deploymentState == 'failed')
        return latest
      else
        return Cms::Deployment.build(:releaseId => options[:releaseId])
      end
    end
  end

  def self.latest(options = {})
    deployment = Cms::Deployment.all(:params => {:latest => 'true'}.merge(options)).first
    check_pausing_state(deployment)
  end

  def self.search(options)
    data = Search::Base.search('/cms/deployment', options)
    return nil unless data

    result = data.map { |r| new(r, true) }
    result.info.clear.merge!(data.info)
    return result
  end

  def self.search_latest_by_ns(ns_path, options = {})
    Search::Base.search_latest_by_ns('/cms/deployment', ns_path, options).map {|r| new(r, true)}
  end

  def to_param
    deploymentId.to_s
  end

  def rfc_cis
    @rfc_cis ||= Cms::DeploymentCi.all( :params => { :deploymentId => self.deploymentId })
  end

  def rfc_relations
    Cms::DeploymentRelation.all( :params => { :deploymentId => self.deploymentId })
  end

  def workorders(params = {})
    self.get(:workorders, params)
  end

  def check_pausing_state
    self.class.check_pausing_state(self)
  end


  private

  def self.check_pausing_state(deployment)
    # if any of the work orders are still "inprogress" the deployment state is "pausing". Backend does not support
    # 'pausing' state (only 'paused') but we introduce new intermediary state 'pausing' to indicate that deployment has
    # not been totally paused and therefore some actions (i.e. 'cancel' and 'resume') would not be allowed until 'paused'
    # state is fully realized (there are no 'inprogress' work orders).
    deployment.deploymentState = 'pausing' if deployment &&
                                              deployment.deploymentState == 'paused' &&
                                              deployment.rfc_cis.find() {|rfc| rfc.dpmtRecordState == 'inprogress'}
    deployment
  end
end
