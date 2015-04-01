require 'spec_helper'

module Admin
  describe EnterprisesController do
    include AuthenticationWorkflow

    let(:user) { create(:user) }
    let(:admin_user) { create(:admin_user) }
    let(:distributor_manager) { create(:user, enterprise_limit: 10, enterprises: [distributor]) }
    let(:supplier_manager) { create(:user, enterprise_limit: 10, enterprises: [supplier]) }
    let(:distributor_owner) { create(:user, enterprise_limit: 10) }
    let(:supplier_owner) { create(:user) }

    let(:distributor) { create(:distributor_enterprise, owner: distributor_owner ) }
    let(:supplier) { create(:supplier_enterprise, owner: supplier_owner) }


    describe "creating an enterprise" do
      let(:country) { Spree::Country.find_by_name 'Australia' }
      let(:state) { Spree::State.find_by_name 'Victoria' }
      let(:enterprise_params) { {enterprise: {name: 'zzz', permalink: 'zzz', email: "bob@example.com", address_attributes: {address1: 'a', city: 'a', zipcode: 'a', country_id: country.id, state_id: state.id}}} }

      it "grants management permission if the current user is an enterprise user" do
        controller.stub spree_current_user: distributor_manager
        enterprise_params[:enterprise][:owner_id] = distributor_manager

        spree_put :create, enterprise_params
        enterprise = Enterprise.find_by_name 'zzz'
        distributor_manager.enterprise_roles.where(enterprise_id: enterprise).first.should be
      end

      it "does not grant management permission to admins" do
        controller.stub spree_current_user: admin_user
        enterprise_params[:enterprise][:owner_id] = admin_user

        spree_put :create, enterprise_params
        enterprise = Enterprise.find_by_name 'zzz'
        admin_user.enterprise_roles.where(enterprise_id: enterprise).should be_empty
      end

      it "overrides the owner_id submitted by the user unless current_user is super admin" do
        controller.stub spree_current_user: distributor_manager
        enterprise_params[:enterprise][:owner_id] = user

        spree_put :create, enterprise_params
        enterprise = Enterprise.find_by_name 'zzz'
        distributor_manager.enterprise_roles.where(enterprise_id: enterprise).first.should be
      end

      context "when I already own a hub" do
        before { distributor }

        it "creates new non-producers as hubs" do
          controller.stub spree_current_user: distributor_owner
          enterprise_params[:enterprise][:owner_id] = distributor_owner

          spree_put :create, enterprise_params
          enterprise = Enterprise.find_by_name 'zzz'
          enterprise.sells.should == 'any'
        end

        it "creates new producers as sells none" do
          controller.stub spree_current_user: distributor_owner
          enterprise_params[:enterprise][:owner_id] = distributor_owner
          enterprise_params[:enterprise][:is_primary_producer] = '1'

          spree_put :create, enterprise_params
          enterprise = Enterprise.find_by_name 'zzz'
          enterprise.sells.should == 'none'
        end

        it "doesn't affect the hub status for super admins" do
          admin_user.enterprises << create(:distributor_enterprise)

          controller.stub spree_current_user: admin_user
          enterprise_params[:enterprise][:owner_id] = admin_user
          enterprise_params[:enterprise][:sells] = 'none'

          spree_put :create, enterprise_params
          enterprise = Enterprise.find_by_name 'zzz'
          enterprise.sells.should == 'none'
        end
      end

      context "when I do not have a hub" do
        it "does not create the new enterprise as a hub" do
          controller.stub spree_current_user: supplier_manager
          enterprise_params[:enterprise][:owner_id] = supplier_manager

          spree_put :create, enterprise_params
          enterprise = Enterprise.find_by_name 'zzz'
          enterprise.sells.should == 'none'
        end

        it "doesn't affect the hub status for super admins" do
          controller.stub spree_current_user: admin_user
          enterprise_params[:enterprise][:owner_id] = admin_user
          enterprise_params[:enterprise][:sells] = 'any'

          spree_put :create, enterprise_params
          enterprise = Enterprise.find_by_name 'zzz'
          enterprise.sells.should == 'any'
        end
      end
    end

    describe "updating an enterprise" do
      let(:profile_enterprise) { create(:enterprise, sells: 'none') }

      context "as manager" do
        it "does not allow 'sells' to be changed" do
          profile_enterprise.enterprise_roles.build(user: distributor_manager).save
          controller.stub spree_current_user: distributor_manager
          enterprise_params = { id: profile_enterprise, enterprise: { sells: 'any' } }

          spree_put :update, enterprise_params
          profile_enterprise.reload
          expect(profile_enterprise.sells).to eq 'none'
        end

        it "does not allow owner to be changed" do
          controller.stub spree_current_user: distributor_manager
          update_params = { id: distributor, enterprise: { owner_id: distributor_manager } }
          spree_post :update, update_params

          distributor.reload
          expect(distributor.owner).to eq distributor_owner
        end

        it "does not allow managers to be changed" do
          controller.stub spree_current_user: distributor_manager
          update_params = { id: distributor, enterprise: { user_ids: [distributor_owner.id,distributor_manager.id,user.id] } }
          spree_post :update, update_params

          distributor.reload
          expect(distributor.users).to_not include user
        end


        describe "enterprise properties" do
          let(:producer) { create(:enterprise) }
          let!(:property) { create(:property, name: "A nice name") }

          before do
            @request.env['HTTP_REFERER'] = 'http://test.com/'
            login_as_enterprise_user [producer]
          end

          context "when a submitted property does not already exist" do
            it "does not create a new property, or product property" do
              spree_put :update, {
                id: producer,
                enterprise: {
                  producer_properties_attributes: {
                    '0' => { property_name: 'a different name', value: 'something' }
                  }
                }
              }
              expect(Spree::Property.count).to be 1
              expect(ProducerProperty.count).to be 0
              property_names = producer.reload.properties.map(&:name)
              expect(property_names).to_not include 'a different name'
            end
          end

          context "when a submitted property exists" do
            it "adds a product property" do
              spree_put :update, {
                id: producer,
                enterprise: {
                  producer_properties_attributes: {
                    '0' => { property_name: 'A nice name', value: 'something' }
                  }
                }
              }
              expect(Spree::Property.count).to be 1
              expect(ProducerProperty.count).to be 1
              property_names = producer.reload.properties.map(&:name)
              expect(property_names).to include 'A nice name'
            end
          end
        end
      end

      context "as owner" do
        it "allows owner to be changed" do
          controller.stub spree_current_user: distributor_owner
          update_params = { id: distributor, enterprise: { owner_id: distributor_manager } }
          spree_post :update, update_params

          distributor.reload
          expect(distributor.owner).to eq distributor_manager
        end

        it "allows managers to be changed" do
          controller.stub spree_current_user: distributor_owner
          update_params = { id: distributor, enterprise: { user_ids: [distributor_owner.id,distributor_manager.id,user.id] } }
          spree_post :update, update_params

          distributor.reload
          expect(distributor.users).to include user
        end
      end

      context "as super admin" do
        it "allows 'sells' to be changed" do
          controller.stub spree_current_user: admin_user
          enterprise_params = { id: profile_enterprise, enterprise: { sells: 'any' } }

          spree_put :update, enterprise_params
          profile_enterprise.reload
          expect(profile_enterprise.sells).to eq 'any'
        end


        it "allows owner to be changed" do
          controller.stub spree_current_user: admin_user
          update_params = { id: distributor, enterprise: { owner_id: distributor_manager } }
          spree_post :update, update_params

          distributor.reload
          expect(distributor.owner).to eq distributor_manager
        end

        it "allows managers to be changed" do
          controller.stub spree_current_user: admin_user
          update_params = { id: distributor, enterprise: { user_ids: [distributor_owner.id,distributor_manager.id,user.id] } }
          spree_post :update, update_params

          distributor.reload
          expect(distributor.users).to include user
        end
      end
    end

    describe "set_sells" do
      let(:enterprise) { create(:enterprise, sells: 'none') }

      before do
        controller.stub spree_current_user: distributor_manager
      end

      context "as a normal user" do
        it "does not allow 'sells' to be set" do
          spree_post :set_sells, { id: enterprise.id, sells: 'none' }
          expect(response).to redirect_to spree.unauthorized_path
        end
      end

      context "as a manager" do
        before do
          enterprise.enterprise_roles.build(user: distributor_manager).save
        end

        context "allows setting 'sells' to 'none'" do
          it "is allowed" do
            spree_post :set_sells, { id: enterprise, sells: 'none' }
            expect(response).to redirect_to spree.admin_path
            expect(flash[:success]).to eq "Congratulations! Registration for #{enterprise.name} is complete!"
            expect(enterprise.reload.sells).to eq 'none'
          end

          context "setting producer_profile_only to true" do
            it "is allowed" do
              spree_post :set_sells, { id: enterprise, sells: 'none', producer_profile_only: true }
              expect(response).to redirect_to spree.admin_path
              expect(enterprise.reload.producer_profile_only).to eq true
            end
          end
        end

        context "setting 'sells' to 'own'" do
          before do
            enterprise.sells = 'own'
            enterprise.save!
          end

          context "if the trial has finished" do
            before do
              enterprise.shop_trial_start_date = (Date.today - 30.days).to_time
              enterprise.save!
            end

            it "is disallowed" do
              spree_post :set_sells, { id: enterprise, sells: 'own' }
              expect(response).to redirect_to spree.admin_path
              trial_expiry = Date.today.strftime("%Y-%m-%d")
              expect(flash[:error]).to eq "Sorry, but you've already had a trial. Expired on: #{trial_expiry}"
              expect(enterprise.reload.sells).to eq 'own'
              expect(enterprise.reload.shop_trial_start_date).to eq (Date.today - 30.days).to_time
            end
          end

          context "if the trial has not finished" do
            before do
              enterprise.shop_trial_start_date = Date.today.to_time
              enterprise.save!
            end

            it "is allowed, but trial start date is not reset" do
              spree_post :set_sells, { id: enterprise, sells: 'own' }
              expect(response).to redirect_to spree.admin_path
              trial_expiry = (Date.today + 30.days).strftime("%Y-%m-%d")
              expect(flash[:notice]).to eq "Welcome back! Your trial expires on: #{trial_expiry}"
              expect(enterprise.reload.sells).to eq 'own'
              expect(enterprise.reload.shop_trial_start_date).to eq Date.today.to_time
            end
          end

          context "if a trial has not started" do
            it "is allowed" do
              spree_post :set_sells, { id: enterprise, sells: 'own' }
              expect(response).to redirect_to spree.admin_path
              expect(flash[:success]).to eq "Congratulations! Registration for #{enterprise.name} is complete!"
              expect(enterprise.reload.sells).to eq 'own'
              expect(enterprise.reload.shop_trial_start_date).to be > Time.now-(1.minute)
            end
          end

          context "setting producer_profile_only to true" do
            it "is ignored" do
              spree_post :set_sells, { id: enterprise, sells: 'own', producer_profile_only: true }
              expect(response).to redirect_to spree.admin_path
              expect(enterprise.reload.producer_profile_only).to be false
            end
          end
        end

        context "setting 'sells' to any" do
          it "is not allowed" do
            spree_post :set_sells, { id: enterprise, sells: 'any' }
            expect(response).to redirect_to spree.admin_path
            expect(flash[:error]).to eq "Unauthorised"
            expect(enterprise.reload.sells).to eq 'none'
          end
        end

        context "settiing 'sells' to 'unspecified'" do
          it "is not allowed" do
            spree_post :set_sells, { id: enterprise, sells: 'unspecified' }
            expect(response).to redirect_to spree.admin_path
            expect(flash[:error]).to eq "Unauthorised"
            expect(enterprise.reload.sells).to eq 'none'
          end
        end
      end
    end

    describe "bulk updating enterprises" do
      let!(:original_owner) do
        user = create_enterprise_user
        user.enterprise_limit = 2
        user.save!
        user
      end
      let!(:new_owner) do
        user = create_enterprise_user
        user.enterprise_limit = 2
        user.save!
        user
      end
      let!(:profile_enterprise1) { create(:enterprise, sells: 'none', owner: original_owner ) }
      let!(:profile_enterprise2) { create(:enterprise, sells: 'none', owner: original_owner ) }

      context "as manager" do
        it "does not allow 'sells' or 'owner' to be changed" do
          profile_enterprise1.enterprise_roles.build(user: new_owner).save
          profile_enterprise2.enterprise_roles.build(user: new_owner).save
          controller.stub spree_current_user: new_owner
          bulk_enterprise_params = { enterprise_set: { collection_attributes: { '0' => { id: profile_enterprise1.id, sells: 'any', owner_id: new_owner.id }, '1' => { id: profile_enterprise2.id, sells: 'any', owner_id: new_owner.id } } } }

          spree_put :bulk_update, bulk_enterprise_params
          profile_enterprise1.reload
          profile_enterprise2.reload
          expect(profile_enterprise1.sells).to eq 'none'
          expect(profile_enterprise2.sells).to eq 'none'
          expect(profile_enterprise1.owner).to eq original_owner
          expect(profile_enterprise2.owner).to eq original_owner
        end

        it "cuts down the list of enterprises displayed when error received on bulk update" do
          EnterpriseSet.any_instance.stub(:save) { false }
          profile_enterprise1.enterprise_roles.build(user: new_owner).save
          controller.stub spree_current_user: new_owner
          bulk_enterprise_params = { enterprise_set: { collection_attributes: { '0' => { id: profile_enterprise1.id, visible: 'false' } } } }
          spree_put :bulk_update, bulk_enterprise_params
          expect(assigns(:enterprise_set).collection).to eq [profile_enterprise1]
        end
      end

      context "as super admin" do
        it "allows 'sells' and 'owner' to be changed" do
          profile_enterprise1.enterprise_roles.build(user: new_owner).save
          profile_enterprise2.enterprise_roles.build(user: new_owner).save
          controller.stub spree_current_user: admin_user
          bulk_enterprise_params = { enterprise_set: { collection_attributes: { '0' => { id: profile_enterprise1.id, sells: 'any', owner_id: new_owner.id }, '1' => { id: profile_enterprise2.id, sells: 'any', owner_id: new_owner.id } } } }

          spree_put :bulk_update, bulk_enterprise_params
          profile_enterprise1.reload
          profile_enterprise2.reload
          expect(profile_enterprise1.sells).to eq 'any'
          expect(profile_enterprise2.sells).to eq 'any'
          expect(profile_enterprise1.owner).to eq new_owner
          expect(profile_enterprise2.owner).to eq new_owner
        end
      end
    end

    describe "for_order_cycle" do
      let!(:user) { create_enterprise_user }
      let!(:enterprise) { create(:enterprise, sells: 'any', owner: user) }
      let(:permission_mock) { double(:permission) }

      before do
        # As a user with permission
        controller.stub spree_current_user: user
        Enterprise.stub find: "instance of Enterprise"
        OrderCycle.stub find: "instance of OrderCycle"

        OpenFoodNetwork::Permissions.stub(:new) { permission_mock }
        allow(permission_mock).to receive :order_cycle_enterprises_for
      end

      context "when no order_cycle or coordinator is provided in params" do
        before { spree_get :for_order_cycle }
        it "returns an empty scope" do
          expect(permission_mock).to have_received(:order_cycle_enterprises_for).with({})
        end
      end

      context "when an order_cycle_id is provided in params" do
        before { spree_get :for_order_cycle, order_cycle_id: 1 }
        it "calls order_cycle_enterprises_for() with an :order_cycle option" do
          expect(permission_mock).to have_received(:order_cycle_enterprises_for).with(order_cycle: "instance of OrderCycle")
        end
      end

      context "when a coordinator is provided in params" do
        before { spree_get :for_order_cycle, coordinator_id: 1 }
        it "calls order_cycle_enterprises_for() with a :coordinator option" do
          expect(permission_mock).to have_received(:order_cycle_enterprises_for).with(coordinator: "instance of Enterprise")
        end
      end

      context "when both an order cycle and a coordinator are provided in params" do
        before { spree_get :for_order_cycle, order_cycle_id: 1, coordinator_id: 1 }
        it "calls order_cycle_enterprises_for() with both options" do
          expect(permission_mock).to have_received(:order_cycle_enterprises_for).with(coordinator: "instance of Enterprise", order_cycle: "instance of OrderCycle")
        end
      end
    end
  end
end
