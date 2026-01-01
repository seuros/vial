# frozen_string_literal: true

vial :base_users, abstract: true do
  base do
    active true
    country "MA"
    email sequence(:email)
  end

  sequence(:email) { |i| "base#{i}@test.local" }
end
