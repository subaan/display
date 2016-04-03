class Design::LocalVariablesController < Base::VariablesController
  def new
    @variable = Cms::DjCi.build({:ciClassName  => 'catalog.Localvar',
                                :nsPath       => design_platform_ns_path(@assembly, @platform)},
                                {:owner => {}})
    respond_to do |format|
      format.js   { render :action => :edit }
      format.json { render_json_ci_response(@variable.present?, @variable) }
    end
  end

  def create
    ns_path    = design_platform_ns_path(@assembly, @platform)
    attrs      = params[:cms_dj_ci].merge(:ciClassName => 'catalog.Localvar', :nsPath => ns_path)
    attr_props = attrs.delete(:ciAttrProps)
    @variable  = Cms::DjCi.build(attrs, attr_props)
    relation   = Cms::DjRelation.build(:nsPath       => ns_path,
                                       :relationName => 'catalog.ValueFor',
                                       :toCiId       => @platform.ciId,
                                       :fromCi       => @variable)

    ok = execute_nested(@variable, relation, :save)
    @variable = relation.fromCi if ok

    respond_to do |format|
      format.js   { ok ? index : render(:action => :edit) }
      format.json { render_json_ci_response(ok, @variable) }
    end
  end


  protected

  def find_parents
    @assembly = locate_assembly(params[:assembly_id])
    @platform = Cms::DjCi.locate(params[:platform_id], assembly_ns_path(@assembly), 'catalog.Platform')
  end

  def find_variables
    @variables = Cms::DjRelation.all(:params => {:ciId              => @platform.ciId,
                                                 :direction         => 'to',
                                                 :relationShortName => 'ValueFor',
                                                 :targetClassName   => 'catalog.Localvar',
                                                 :attrProps         => 'owner'}).map(&:fromCi)
  end

  def find_variable
    @variable = Cms::DjCi.locate(params[:id], design_platform_ns_path(@assembly, @platform), 'catalog.Localvar', :attrProps => 'owner')
  end
end
