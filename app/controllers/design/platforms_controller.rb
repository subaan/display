class Design::PlatformsController < Base::PlatformsController
  before_filter :find_assembly_and_platform

  swagger_controller :platforms, 'Design Platform Management'

  swagger_api :index do
    summary 'Fetches all platforms in the design of assembly.'
    notes 'This fetches all platforms from design including new platforms from open release.'
    param_org_name
    param_parent_ci_id :assembly
    response :unauthorized
  end

  def index
    @platforms = Cms::DjRelation.all(:params => {:ciId              => @assembly.ciId,
                                                 :direction         => 'from',
                                                 :relationShortName => 'ComposedOf',
                                                 :targetClassName   => 'catalog.Platform'}).map(&:toCi)
    render :json => @platforms
  end

  def new
    @platform = Cms::DjCi.build({:nsPath      => assembly_ns_path(@assembly),
                                 :ciClassName => 'catalog.Platform'},
                                {:owner => {}})

    respond_to do |format|
      format.html do
        build_linkable_platform_map
        render :action => :new
      end

      format.json { render_json_ci_response(true, @platform) }
    end
  end

  def create
    platform_hash = params[:cms_dj_ci].merge(:nsPath => assembly_ns_path(@assembly), :ciClassName => 'catalog.Platform')
    platform_hash[:ciAttributes][:major_version] = 1
    platform_hash[:ciAttributes][:description] ||= ''
    attr_props = platform_hash.delete(:ciAttrProps)
    @platform = Transistor.create_platform(@assembly.ciId, Cms::DjCi.build(platform_hash, attr_props))
    ok = @platform.errors.empty?

    save_platform_links if ok

    respond_to do |format|
      format.html do
        if ok
          show
        else
          if @platform
            setup_linkable_platform_map
            render :action => :new
          else
            flash[:error] = 'Failed to create platform.'
            new
          end
        end
      end

      format.json { render_json_ci_response(ok, @platform) }
    end
  end

  def edit
    respond_to do |format|
      format.js   { build_linkable_platform_map }
      format.json { render_json_ci_response(true, @platform) }
    end
  end

  def update
    ok = execute(@platform, :update_attributes, params[:cms_dj_ci])
    ok = save_platform_links if ok

    respond_to do |format|
      format.js do
        if ok
          setup_linkable_platform_map()
        end
        render :action => :edit
      end

      format.json { render_json_ci_response(ok, @platform) }
    end
  end

  def destroy
    ok = Transistor.delete_platform(@assembly.ciId, @platform)
    respond_to do |format|
      format.html do
        flash[:error] = "Failed to delete platform. #{@platform.errors.full_messages.join('. ')}" unless ok
        redirect_to(assembly_design_path(@assembly))
      end

      format.json { render_json_ci_response(ok, @platform) }
    end
  end

  def new_clone
    @assemblies = locate_assemblies
  end

  def clone
    @to_assembly  = locate_assembly(params[:to_assembly_id])
    id = Transistor.clone_platform(@platform.ciId, {:nsPath => assembly_ns_path(@to_assembly), :ciClassName => 'catalog.Platform', :ciName => params[:to_ci_name]})
    @to_platform  = Cms::DjCi.find(id) if id
    ok = @to_platform.present?
    flash[:error] = "Failed to clone platform '#{@platform.ciName}'." unless ok

    respond_to do |format|
      format.js
      format.json { render_json_ci_response(ok, @to_platform, ['Failed to clone.']) }
    end
  end

  def component_types
    exising_map = Cms::DjRelation.all(:params => {:ciId              => @platform.ciId,
                                                  :direction         => 'from',
                                                  :relationShortName => 'Requires'}).inject({}) do |m, r|
      m[r.relationAttributes.template] = (m[r.relationAttributes.template] || 0) + 1
      m
    end

    result = get_platform_requires_relation_temlates(@platform).inject({}) do |m, r|
      template_name    = r.toCi.ciName.split('::').last
      cardinality      = r.relationAttributes.constraint.gsub('*', '999').split('..')
      m[template_name] = {:min => cardinality.first.to_i, :max => cardinality.last.to_i, :current => exising_map[template_name] || 0}
      m
    end

    render :json => result
  end

  def diff
    clazz = params[:committed] == 'true' ? Cms::Relation : Cms::DjRelation
    changes_only = params[:changes_only] != 'false'

    # Compare components.
    pack_components = Cms::Relation.all(:params => {:nsPath            => platform_pack_design_ns_path(@platform),
                                                    :relationShortName => 'Requires',
                                                    :includeFromCi     => false,
                                                    :includeToCi       => true}).inject({}) do |m, r|
      m[r.toCi.ciName] = r.toCi
      m
    end

    @diff = clazz.all(:params => {:ciId              => @platform.ciId,
                                  :direction         => 'from',
                                  :relationShortName => 'Requires'}).inject([]) do |m, r|
      component      = r.toCi
      pack_component = pack_components[r.relationAttributes.template]
      component_diff = calculate_ci_diff(component, pack_component)
      # The last condition below is to ensure that we include current component as diff when it is not required by
      # the pack (lower bound of cardinality constraint is zero) even it did not override any defaults when added by user.
      if !changes_only || component_diff.present? || r.relationAttributes.constraint.split('..').first.to_i == 0
        component.diffCi = pack_component
        component.diffAttributes = component_diff
        m << component
      end
      m
    end

    # Compare variables.
    pack_variables = Cms::Relation.all(:params => {:nsPath            => platform_pack_design_ns_path(@platform),
                                                    :relationShortName => 'ValueFor',
                                                    :includeFromCi     => true,
                                                    :includeToCi       => false}).inject({}) do |m, r|
      m[r.fromCi.ciName] = r.fromCi
      m
    end
    clazz.all(:params => {:nsPath            => design_platform_ns_path(@assembly, @platform),
                          :relationShortName => 'ValueFor',
                          :includeFromCi     => true,
                          :includeToCi       => true}).inject(@diff) do |m, r|
      variable      = r.fromCi
      pack_variable = pack_variables[variable.ciName]
      variable_diff = calculate_ci_diff(variable, pack_variable)
      # The last condition below is to ensure that we include current variable as diff when it was in the pack
      # even it does not have any attributes (namely, 'value') set.
      if !changes_only || variable_diff.present? || !pack_variable
        variable.diffCi         = pack_variable
        variable.diffAttributes = variable_diff
        m << variable
      end
      m

    end

    # There are not attachments in the pack so all attachments are added to diff.
    clazz.all(:params => {:nsPath            => design_platform_ns_path(@assembly, @platform),
                          :relationShortName => 'EscortedBy',
                          :includeFromCi     => true,
                          :includeToCi       => true}).inject(@diff) do |m, r|
      attachment = r.toCi
      set_component(attachment, r.fromCi)
      attachment.diffCi         = nil
      attachment.diffAttributes = calculate_ci_diff(attachment, Cms::Ci.build(:ciClassName => 'catalog.Attachment'))
      @diff << attachment
    end

    respond_to do |format|
      format.js
      format.json {render :json => @diff}
    end
  end


  private

  def find_assembly_and_platform
    @assembly = locate_assembly(params[:assembly_id])
    platform_id = params[:id]
    if platform_id.present?
      @platform = Cms::DjCi.locate(platform_id, assembly_ns_path(@assembly), 'catalog.Platform', :attrProps => 'owner')
    end
  end

  def build_linkable_platform_map
    if @platform.new_record?
      linkable_platform_map = find_all_platforms.inject({}) { |m, p| m[p] = false; m }
    else
      all_platforms = find_all_platforms

      links_to_relations = Cms::DjRelation.all(:params => {:nsPath        => @platform.nsPath,
                                                           :fromClassName => 'catalog.Platform',
                                                           :toClassName   => 'catalog.Platform',
                                                           :relationName  => 'catalog.LinksTo'})

      linked_platform_ids = find_linked_platform_ids(links_to_relations, @platform.ciId)
      linked_platform_ids << @platform.ciId
      linked_platform_ids.uniq!
      linkable_platform_map = all_platforms.reject {|p| linked_platform_ids.include?(p.ciId) }.inject({}) do |m, p|
        m[p] = links_to_relations.detect {|r| r.fromCiId == @platform.ciId && r.toCiId == p.ciId}
        m
      end
    end

    @linkable_platform_map =  linkable_platform_map
  end

  def setup_linkable_platform_map
    new_links_to_ids = (params[:links_to].presence || []).map(&:to_i)
    build_linkable_platform_map
    @linkable_platform_map.keys.each { |p| @linkable_platform_map[p] = new_links_to_ids.include?(p.ciId) }
  end

  def find_all_platforms
    Cms::DjCi.all(:params => {:nsPath => @platform.nsPath, :ciClassName => 'catalog.Platform'})
  end

  def find_linked_platform_ids(relations, platform_ids)
    result = []
    platform_ids = [ platform_ids ] unless platform_ids.is_a?(Array)
    platform_ids.each do |p_id|
      relations.each { |r| result << r.fromCiId if r.toCiId == p_id }
    end
    result += find_linked_platform_ids(relations, result) if result.present?
    return result
  end

  def save_platform_links
    new_links_to_ids = (params[:links_to].presence || []).map do |id|
      begin
        Cms::DjCi.locate(id, assembly_ns_path(@assembly), 'catalog.Platform').ciId.to_i
      rescue
        nil
      end
    end
    new_links_to_ids.compact!

    old_links_to_relations = Cms::DjRelation.all(:params => {:ciId => @platform.ciId, :direction => 'from', :relationName => 'catalog.LinksTo'})
    old_links_to_ids       = old_links_to_relations.map(&:toCiId)

    ok = true

    # Destroy relations to platforms that became unlinked.
    (old_links_to_ids - new_links_to_ids).each do |platform_id|
      relation = old_links_to_relations.detect { |r| r.toCiId == platform_id }
      ok       = execute_nested(@platform, relation, :destroy)
      break unless ok
    end

    # Create relations to platforms that became linked.
    if ok
      (new_links_to_ids - old_links_to_ids).each do |platform_id|
        relation = Cms::DjRelation.build({:nsPath       => @platform.nsPath,
                                          :relationName => 'catalog.LinksTo',
                                          :fromCiId     => @platform.ciId,
                                          :toCiId       => platform_id})
        ok = execute_nested(@platform, relation, :save)
        break unless ok
      end
    end

    return ok
  end

  def set_component(ci, component)
    ci.component = Cms::Ci.new(:ciId => component.ciId, :ciClassName => component.ciClassName, :ciName => component.ciName)
  end
end
