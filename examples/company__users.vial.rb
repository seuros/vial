# frozen_string_literal: true

vial :company__users do
  base do
    active true
    company_id erb("<%= ActiveRecord::FixtureSet.identify(:acme) %>")
  end

  generate 1
end
