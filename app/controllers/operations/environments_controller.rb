class Operations::EnvironmentsController < Base::EnvironmentsController
  include ::NotificationSummary, ::CostSummary

  before_filter :find_assembly_and_environment

  def index
    @environments = Cms::Relation.all(:params => {:ciId              => @assembly.ciId,
                                                  :direction         => 'from',
                                                  :relationShortName => 'RealizedIn',
                                                  :targetClassName   => 'manifest.Environment'}).map(&:toCi)
    render :json => @environments
  end

  def show
    respond_to do |format|
      format.html do
        @release     = Cms::Release.latest(:nsPath => environment_manifest_ns_path(@environment))
        @bom_release = Cms::Release.first(:params => {:nsPath       => "#{environment_ns_path(@environment)}/bom",
                                                      :releaseState => 'open'})

        @deployment = Cms::Deployment.latest(:nsPath => "#{environment_ns_path(@environment)}/bom")
        if @deployment && @deployment.deploymentState == 'pending'
          @pending_approvals = Cms::DeploymentApproval.all(:params => {:deploymentId => @deployment.deploymentId}).select { |a| a.state == 'pending' }
        end

        @platforms = Cms::DjRelation.all(:params => {:ciId              => @environment.ciId,
                                                     :direction         => 'from',
                                                     :relationShortName => 'ComposedOf',
                                                     :targetClassName   => 'manifest.Platform'})
        @clouds    = Cms::Relation.all(:params => {:relationName    => 'base.Consumes',
                                                   :targetClassName => 'account.Cloud',
                                                   :direction       => 'from',
                                                   :ciId            => @environment.ciId})

        load_platform_cloud_instances_map
        @ops_states = Operations::Sensor.states(@deloyed_to_rels.map(&:fromCiId))
      end

      format.json { render_json_ci_response(true, @environment) }
    end
  end

  def graph
    @assembly    = Cms::Ci.find(params[:assembly_id])
    @environment = Cms::Ci.find(params[:id])

    manifest_ns_path = environment_manifest_ns_path(@environment)
    composedof_rels = Cms::DjRelation.all(:params => {:ciId              => @environment.ciId,
                                                      :direction         => 'from',
                                                      :relationShortName => 'ComposedOf',
                                                      :targetClassName   => 'manifest.Platform',
                                                      :includeToCi       => true})

    requires_rels = Cms::Relation.all(:params => {:nsPath            => manifest_ns_path,
                                                  :relationShortName => 'Requires',
                                                  :recursive         => true,
                                                  :includeToCi       => true})

    @instances = Cms::DjCi.all(:params => {:nsPath    => environment_ns_path(@environment) + '/bom',
                                           :recursive => true})

    if @instances.size > 500
      @graph = environment_graph(@environment, composedof_rels, requires_rels)
    else
      cis_bom = @instances.inject({}) { |h, c| h.update(c.ciId => c) }
      realizedas_rels = Cms::DjRelation.all(:params => {:nsPath            => environment_ns_path(@environment) + '/bom',
                                                        :relationShortName => 'RealizedAs',
                                                        :recursive         => true})

      ops_states = Operations::Sensor.states(@instances)
      @graph = environment_graph(@environment, composedof_rels, requires_rels, realizedas_rels, cis_bom, ops_states)
    end
  end


  protected

  def search_ns_path
    environment_ns_path(@environment)
  end


  private

  def find_assembly_and_environment
    @assembly = locate_assembly(params[:assembly_id])
    environment_id = params[:id]
    @environment = locate_environment(environment_id, @assembly) if environment_id
  end

  def environment_graph(e, composedof_rels, requires_rels, realizedas_rels = nil, instances = nil, ops_states = nil)
    t            = HashWithIndifferentAccess.new
    t[:name]     = e.ciName
    t[:pkg]      = e.ciClassName.split('.').shift
    t[:klass]    = e.ciClassName.split('.').last
    t[:children] = Array.new
    composedof_rels.each do |p|
      platform = {:name     => p.toCi.ciName,
                  :pkg      => p.toCi.ciClassName.split('.').shift,
                  :klass    => p.toCi.ciClassName.split('.').last,
                  :size     => 10,
                  :children => Array.new}
      requires_rels.select { |r| r.fromCiId == p.toCiId }.each do |c|
        component = {:name     => c.toCi.ciName,
                     :pkg      => c.toCi.ciClassName.split('.').shift,
                     :klass    => c.toCi.ciClassName.split('.').last,
                     :size     => 10,
                     :children => Array.new,
                     :url      => assembly_operations_environment_platform_component_path(@assembly, @environment, p.toCiId, c.toCiId)}
        if realizedas_rels
          realizedas_rels.select { |r| r.fromCiId == c.toCiId }.each do |i|
            instance = instances[i.toCiId]
            component[:children].push({:name       => instance.ciName,
                                       :pkg        => instance.ciClassName.split('.').shift,
                                       :klass      => instance.ciClassName.split('.').last,
                                       :size       => 10,
                                       :release    => instance.rfcAction,
                                       :deployment => instance.rfcId == instance.lastAppliedRfcId ? 'complete' : 'pending',
                                       :health     => instance.lastAppliedRfcId ? ops_states[i.toCiId] : 'pending',
                                       :url        => assembly_operations_environment_platform_component_instance_path(@assembly, @environment, p.toCiId, c.toCiId, i.toCiId)})
          end
        end
        platform[:children].push(component)
      end
      t[:children].push(platform)
    end
    return t
  end
end
