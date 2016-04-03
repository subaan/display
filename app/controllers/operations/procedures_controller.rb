class Operations::ProceduresController < ApplicationController
  before_filter :find_procedure, :except => [:index, :new, :prepare, :create, :log_data]

  helper_method :allow_access?

  def index
    anchor_ci_id = params[:ciId]
    return unauthorized unless allow_access?(anchor_ci_id, true)

    @procedures = Cms::Procedure.all(:params => {:ciId => anchor_ci_id})

    respond_to do |format|
      format.js
      format.json { render :json => @procedures }
    end
  end

  def show
    return unauthorized unless allow_access?(@procedure.ciId, true)
    respond_to do |format|
      format.js { load_action_cis }
      format.json {render_json_ci_response(true, @procedure)}
    end
  end

 def new
    @procedure = Cms::Procedure.build(params)
    @procedure.ciId = params[:ciId]
    return unauthorized unless allow_access?(@procedure.ciId, false)

    procedure_ci_id = params[:procedureCiId]
    if procedure_ci_id.to_i > 0
      procedure_ci = Cms::Ci.find(procedure_ci_id)
      @procedure.procedureName = procedure_ci.ciName
      unless @procedure.arglist.present?
        arguments_json = procedure_ci.ciAttributes.arguments
        build_arglist(arguments_json) if arguments_json.present?
      end
    else
      name = params[:actionName]
      procedure_name = params[:procedureName].presence || name
      @procedure.procedureName = procedure_name

      unless @procedure.arglist.present?
        ci_class_name = params[:actionCiClassName]
        if ci_class_name.present?
          md        = Cms::CiMd.look_up(ci_class_name)
          md_action = md && md.actions.find { |a| a.actionName == name }
          if md_action && md_action.arguments.present?
            build_arglist(md_action.arguments)
          end
        end
      end

      @target_ids = params[:actionCiIds]
      attachment_ci_id = params[:attachmentCiId].to_i
      action = {:actionName => name, :stepNumber => 1, :isCritical => true}
      action[:extraInfo] = attachment_ci_id if attachment_ci_id > 0
      if @target_ids
        full_flow = flow = []
        direction = params[:direction] || 'from'
        relation_names = (params[:relationName] || 'base.RealizedAs').split(',')
        relation_names[0..-2].each do |relation_name|
          flow << {:relationName => relation_name,
                   :direction    => direction,
                   :flow         => []}
          flow = flow.first[:flow]
        end
        flow << {:relationName => relation_names[-1],
                 :direction    => direction,
                 :targetIds    => @target_ids,
                 :actions      => [action]}
        @procedure.definition = {:name => procedure_name, :flow => full_flow}.to_json
      else
        @procedure.definition = {:name => procedure_name, :flow => [], :actions => [action]}.to_json
      end
    end
    render(:action => :new)
 end

  # This is POST version of "new" for situations when 'actionCiIds' list is long and GET url length is restricted.
  def prepare
    new
  end

  def create
    @procedure = Cms::Procedure.build(params[:cms_procedure])
    return unauthorized unless allow_access?(@procedure.ciId, false)

    roll_at = params[:roll_at].to_i
    if roll_at >= 1 && roll_at < 100
      definition = JSON.parse(@procedure.definition)
      if definition['flow'].present?
        old_last_node = definition['flow'].first
        old_flow_json = old_last_node.to_json
        old_last_node = old_last_node['flow'].first while old_last_node['flow'].present?
        target_ids = old_last_node['targetIds']
        actions = [{:isCritical => params[:critical]}.reverse_merge(old_last_node['actions'].first)]
        new_flow = []
        roll_at = 10 if roll_at < 1
        step_size = [0, (target_ids.size * roll_at / 100)].max
        (target_ids.size.to_f / step_size).ceil.times do |step|
          new_flow << JSON.parse(old_flow_json)
          new_last_node = new_flow.last
          new_last_node = new_last_node['flow'].first while new_last_node['flow'].present?
          new_last_node['targetIds'] = target_ids[(step_size * step)...(step_size * (step + 1))]
          new_last_node['actions']   = actions
        end
        @procedure.definition = {:name => definition['name'], :flow => new_flow}.to_json
      end
    end

    ok = execute(@procedure, :save)
    respond_to do |format|
      format.js do
        if ok
          flash[:notice] = 'Procedure execution was successfully started.'
          render_edit
        else
          flash[:error] = "Failed to start procedure#{" (#{@procedure.errors.full_messages})" if @procedure.errors.present?}."
          render :nothing => true
        end
      end

      format.json {render_json_ci_response(ok, @procedure)}
    end
  end

  def edit
    return unauthorized unless allow_access?(@procedure.ciId, true)
    render_edit
  end

  def update
    return unauthorized unless allow_access?(@procedure.ciId, false)
    if params[:cms_procedure][:procedureState] == 'active'
      ok = execute(@procedure, :retry)
      # another lookup needed to get the full object again with actionorders
      @procedure = Cms::Procedure.find(params[:id]) if ok
    else
      ok = execute(@procedure, :update_attributes, params[:cms_procedure])
    end

    respond_to do |format|
      format.js { render_edit }

      format.json {render_json_ci_response(ok, @procedure)}
    end
  end

  def status
    return unauthorized unless allow_access?(@procedure.ciId, true)

    @procedure_actions_states = @procedure.actions.inject({}) { |states, action| states[action.actionId] = action.actionState; states }
    @procedure.log_data = pull_log_data(params[:action_ids] || [])

    respond_to do |format|
      format.js
      format.json { render_json_ci_response(@procedure.present?, @procedure) }
    end
  end

  def log_data
    @procedure = Cms::Procedure.find(params[:procedure_id])
    return unauthorized unless allow_access?(@procedure.ciId, true)

    @procedure.log_data = pull_log_data(params[:action_ids] || @procedure.actions.map(&:actionId)) if @procedure
    respond_to do |format|
      format.js
      format.json { render_json_ci_response(@procedure.present?, @procedure) }
    end
  end


  private

  def find_procedure
    @procedure = Cms::Procedure.find(params[:id])
  end

  def pull_log_data(action_ids)
    Daq.logs(action_ids.map {|id| {:id => id}}).inject({}) {|m, e| m[e['id']] = e['logData']; m}
  end

  def load_action_cis
    cis = {}
    ci_ids = @procedure.actions.map(&:ciId)
    ci_ids.each_slice(100) do |ids|
      cis = Cms::Ci.all(:params => {:ids => ids.join(',')}).inject(cis) do |h, ci|
        h[ci.ciId] = ci
        h
      end
    end

    @procedure.actions.each { |action| action.ci = cis[action.ciId] }
  end

  def render_edit
    load_action_cis
    render :action => :edit
  end

  def allow_access?(anchor_ci_id, read_only)
    unless @anchor_ci
      begin
        @anchor_ci = Cms::Ci.find(anchor_ci_id)
      rescue Exception => e
      end
    end
    return false unless @anchor_ci

    root, org, assembly, other = @anchor_ci.nsPath.split('/')
    if assembly && !assembly.start_with?('_')
      return read_only ? current_user.has_any_dto?(assembly) : has_operations?(assembly)
    elsif @anchor_ci.ciClassName == 'account.Cloud'
      return has_cloud_services?(@anchor_ci.ciId) || has_cloud_support?(@anchor_ci.ciId)
    end
    return is_admin?
  end

  def build_arglist(arguments_json)
    begin
      arguments = JSON.parse(arguments_json)
    rescue Exception => e
      Rails.logger.warn "Failed to parse arguments definition for action #{md_action.to_json}"
    end
    if arguments.present?
      arglist = arguments.values.inject({}) do |m, arg|
        m[arg['name']] = arg['defaultValue']
        m
      end
      @procedure.arglist = arglist.to_json
    end
  end
end
