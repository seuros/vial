# frozen_string_literal: true

vial :admin_users do
  include_vial :base_users do
    override :role, "admin"
  end

  generate 2
end
