FactoryGirl.define do
  factory :hcm do
    institution { Faker::University.name }

    city { Faker::Address.city }
    sequence :state do |n| DS_ENUM::State::STATES.keys[n % DS_ENUM::State::STATES.keys.length] end
    sequence :ope do |n| n.to_s(32).rjust(8, "0") end

    monitor_method { ["HCM - Cash Monitoring 1", "HCM - Cash Monitoring 2"].sample }
    reason { ["Financial Responsibility", 
      "Audit Late/Missing", "Program Review", "Other -CIO Problems (Eligibility)",
      "F/S Late/Missing", "Program Review - Severe Findings", "OIG", 
      "Denied Recert - PPA Not Expired", "Payment Method Changed", 
      "Accreditation Problems", "Administrative Capability",
      "Provisional Certification"
      ].sample 
    }
  end
end