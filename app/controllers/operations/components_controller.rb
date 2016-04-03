class Operations::ComponentsController < ApplicationController
  before_filter :find_parents_and_component

  def index
    @components = Cms::Relation.all(:params => {:ciId         => @platform.ciId,
                                                :direction    => 'from',
                                                :includeToCi  => true,
                                                :relationName => 'manifest.Requires'}).map(&:toCi)

    render :json => @components
  end

  def show
    respond_to do |format|
      format.html { @procedures = Cms::Procedure.all(:params => {:ciId => @component.ciId}) }
      format.json {render_json_ci_response(true, @component)}
    end
  end

  def actions
    actions = @component.meta.actions + Operations::InstancesController.load_custom_actions(@component)
    render :json => actions
  end

  def charts
    all_instance_ids = Cms::Relation.all(:params => {:ciId              => @component.ciId,
                                                 :direction         => 'from',
                                                 :relationShortName => 'RealizedAs',
                                                 :includeToCi       => false}).map(&:toCiId)
    instance_ids = params[:instance_ids]
    if instance_ids.blank?
      instance_ids = all_instance_ids
    else
      instance_ids = all_instance_ids & instance_ids.map(&:to_i)
    end

    metrics = params[:metrics]
    if metrics.blank?
      metrics = Cms::DjRelation.all(:params => {:ciId              => @component.ciId,
                                                 :direction         => 'from',
                                                 :relationShortName => 'WatchedBy',
                                                 :includeToCi       => true}).map(&:toCi).inject([]) do |a, monitor|
        monitor_name = monitor.ciName
        a + ActiveSupport::JSON.decode(monitor.ciAttributes.metrics).keys.map {|m| "#{monitor_name}:#{m}"}
      end
    end

    start_time = params[:start_time].to_i
    end_time   = params[:end_time].to_i
    step       = params[:step].to_i
    unless start_time > 0 && step > 0 && end_time > start_time
      range        = params[:range] || 'hour'
      step         = Operations::MonitorsController::CHART_TIME_RANGE_STEP[range]
      range_length = Operations::MonitorsController::CHART_TIME_RANGE_LENGTH[range]
      current_time = Time.now.to_i
      end_time     = current_time - (current_time % step)
      start_time   = end_time - range_length
    end

    data = Daq.charts(instance_ids.map { |id| {:ci_id   => id,
                                               :start   => start_time,
                                               :end     => end_time,
                                               :step    => step,
                                               :metrics => metrics} })

    render :json => data
  end


  private

  def find_parents_and_component
    @assembly    = locate_assembly(params[:assembly_id])
    @environment = locate_environment(params[:environment_id], @assembly)
    @platform    = locate_manifest_platform(params[:platform_id], @environment)
    component_id = params[:id]
    @component   = Cms::DjCi.locate(component_id, @platform.nsPath) if component_id.present?
  end
end
