Rails.application.routes.draw do
  resources :outcomes
  resources :complaints
  resources :data_csvs
  resources :ipeds_ic_pies
  resources :ipeds_ic_ays
  resources :ipeds_hds
  resources :ipeds_ics
  resources :settlements
  resources :hcms
  resources :mous
  resources :sec702_schools
  resources :sec702s
  resources :svas
  resources :vsocs
  resources :p911_yrs
  resources :p911_tfs
  resources :arf_gibills
  resources :accreditations
  resources :scorecards
  resources :eight_keys
  resources :va_crosswalks
  resources :weams
  
  root 'dashboards#index' 

  resources :dashboards, only: [:index, :create]
  resources :csv_files, only: [:show, :index, :create, :destroy]

  get 'csv_files/:id/send_csv_file' => 'csv_files#send_csv_file', as: :send_csv_file
  get 'csv_files/new/(:type)' => 'csv_files#new', as: :new_csv_file

  get 'dashboards/export(.:format)' => 'dashboards#export', as: :dashboards_export_csv_file
  get 'dashboards/db_push/:srv/(.:format)' => 'dashboards#db_push', as: :dashboards_db_push
  
  devise_for :users
  # The priority is based upon order of creation: first created -> highest priority.
  # See how all your routes lay out with "rake routes".

  # You can have the root of your site routed with "root"
  # root 'welcome#index'

  # Example of regular route:
  #   get 'products/:id' => 'catalog#view'

  # Example of named route that can be invoked with purchase_url(id: product.id)
  #   get 'products/:id/purchase' => 'catalog#purchase', as: :purchase

  # Example resource route (maps HTTP verbs to controller actions automatically):
  #   resources :products

  # Example resource route with options:
  #   resources :products do
  #     member do
  #       get 'short'
  #       post 'toggle'
  #     end
  #
  #     collection do
  #       get 'sold'
  #     end
  #   end

  # Example resource route with sub-resources:
  #   resources :products do
  #     resources :comments, :sales
  #     resource :seller
  #   end

  # Example resource route with more complex sub-resources:
  #   resources :products do
  #     resources :comments
  #     resources :sales do
  #       get 'recent', on: :collection
  #     end
  #   end

  # Example resource route with concerns:
  #   concern :toggleable do
  #     post 'toggle'
  #   end
  #   resources :posts, concerns: :toggleable
  #   resources :photos, concerns: :toggleable

  # Example resource route within a namespace:
  #   namespace :admin do
  #     # Directs /admin/products/* to Admin::ProductsController
  #     # (app/controllers/admin/products_controller.rb)
  #     resources :products
  #   end
end
