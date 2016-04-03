class AddDescriptionToTeams < ActiveRecord::Migration
  def up
    add_column :teams, :description, :text
    Team.update_all(['description = ?', 'Most powerful users with full spectrum of permissions.'], ['name = ?', Team::ADMINS])
    add_index :teams, [:organization_id, :name], :unique => true
  end

  def down
    remove_column :teams, :description
    remove_index :teams, [:organization_id, :name]
  end
end
