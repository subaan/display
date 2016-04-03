class RedirectController < ApplicationController
  skip_before_filter :authenticate_user!, :check_eula, :check_organization, :check_reset_password, :check_username, :set_active_resource_headers
  before_filter :clear_active_resource_headers
  before_filter :find_ci, :only => [:ci, :instance, :monitor_doc]

  def ns
    redirect_to path_to_ns(params[:path])
  end

  def release
    begin
      release = Cms::Release.find(params[:id])
    rescue
    end

    if release
      redirect_to path_to_release(release)
    else
      render :text => 'Release not found'
     end
  end

  def deployment
    begin
      deployment = Cms::Deployment.find(params[:id])
    rescue
    end

    if deployment
      redirect_to path_to_deployment(deployment)
    else
      render :text => 'Deployment not found'
     end
  end

  def procedure
    procedure = Cms::Procedure.find(params[:id])
    ci = procedure && Cms::DjCi.find(procedure.ciId)
    if ci
      redirect_to "#{path_to_ci(ci, 'operations')}#procedures/list_item/#{procedure.procedureId}"
    else
      render :text => 'Procedure not found'
    end
  end

  def ci
    redirect_to path_to_ci(@ci, params[:dto])
  end

  def instance
    foo, org, assembly, env, bom, platform, version = @ci.nsPath.split('/')
    redirect_to assembly_operations_environment_platform_instance_path(:org_name       => org,
                                                                       :assembly_id    => assembly,
                                                                       :environment_id => env,
                                                                       :platform_id    => platform,
                                                                       :id             => @ci.ciId)
  end

  def monitor_doc
    @component_id = Cms::DjRelation.first(:params => {:ciId              => @ci.ciId,
                                                      :direction         => 'to',
                                                      :relationShortName => 'RealizedAs'}).fromCiId

    monitor_name = params[:monitor]
    monitor = Cms::DjRelation.all(:params => {:ciId              => @component_id,
                                              :direction         => 'from',
                                              :relationShortName => 'WatchedBy',
                                              :includeToCi       => true}).find { |m| m.toCi.ciName == monitor_name }
    unless monitor
      render :text => 'Monitor not found'
      return
    end
    url = monitor.relationAttributes.docUrl.strip
    if url.present?
      redirect_to url
    else
      render :text => 'No doc URL found'
    end
  end


  private

  def find_ci
    begin
      ci_id = params[:id]
      @ci = Cms::DjCi.find(ci_id)
    rescue
    end

    unless @ci
      flash[:error] = "Instance #{ci_id} not found."
      redirect_to :root
    end
  end
end
