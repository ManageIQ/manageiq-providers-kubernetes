describe ContainerGroup do
  it "has distinct images" do
    group = FactoryGirl.create(
      :container_group,
      :name => "group",
    )
    FactoryGirl.create(
      :container_image,
      :containers => [FactoryGirl.create(:container, :name => "container_a", :container_group => group),
                      FactoryGirl.create(:container, :name => "container_b", :container_group => group)]
    )
    expect(group.container_images.count).to eq(1)
  end

  # check https://bugzilla.redhat.com/show_bug.cgi?id=1406770
  it "has container volumes" do
    pvc = FactoryGirl.create(
      :persistent_volume_claim,
      :name => "test_claim"
    )

    group = FactoryGirl.create(
      :container_group,
      :name => "group",
    )

    ems = FactoryGirl.create(
      :ems_kubernetes,
      :id   => group.id,
      :name => "ems"
    )

    container_volume = FactoryGirl.create(
      :container_volume,
      :name                    => "container_volume",
      :type                    => 'ContainerVolume',
      :parent                  => group,
      :persistent_volume_claim => pvc
    )

    persistent_volume = FactoryGirl.create(
      :persistent_volume,
      :name                    => "persistent_volume",
      :parent                  => ems,
      :persistent_volume_claim => pvc
    )

    assert_pv_to_pod_relationship(persistent_volume)
    assert_volumes_relations(group, ems, container_volume, persistent_volume)

    group.container_volumes.destroy_all
    ems.persistent_volumes.destroy_all
    container_volume = group.container_volumes.create(:name => "container_volume")
    persistent_volume = ems.persistent_volumes.create(:name => "persistent_volume")
    assert_volumes_relations(group, ems, container_volume, persistent_volume)
  end

  def assert_volumes_relations(group, ems, container_volume, persistent_volume)
    expect(group.container_volumes.count).to eq(1)
    expect(group.container_volumes.first.name).to eq("container_volume")
    expect(ems.persistent_volumes.count).to eq(1)
    expect(ems.persistent_volumes.first.name).to eq("persistent_volume")
    expect(container_volume.parent.class).to eq(ContainerGroup)
    expect(container_volume.parent.name).to eq("group")
    expect(container_volume.parent_type).to eq("ContainerGroup")
    expect(persistent_volume.parent.class).to eq(ManageIQ::Providers::Kubernetes::ContainerManager)
    expect(persistent_volume.parent.name).to eq("ems")
    expect(persistent_volume.parent_type).to eq("ExtManagementSystem")
  end

  def assert_pv_to_pod_relationship(persistent_volume)
    expect(persistent_volume.container_volumes.first.name).to eq("container_volume")
    expect(persistent_volume.container_volumes.count).to eq(1)
    expect(persistent_volume.container_groups.first.name).to eq("group")
    expect(persistent_volume.container_groups.count).to eq(1)
  end
end
