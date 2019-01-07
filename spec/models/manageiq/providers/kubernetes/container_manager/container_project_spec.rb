describe ContainerProject do
  it "has distinct nodes" do
    node = FactoryBot.create(:container_node, :name => "n")
    expect(FactoryBot.create(
    :container_project,
    :container_groups => [FactoryBot.create(:container_group, :name => "g1", :container_node => node),
                          FactoryBot.create(:container_group, :name => "g2", :container_node => node)]
    ).container_nodes.count).to eq(1)
  end

  it "has distinct images" do
    # Create a project with 2 containers from different pods that run the same image
    node = FactoryBot.create(:container_node, :name => "n")
    group = FactoryBot.create(
      :container_group,
      :name           => "group",
      :container_node => node
    )
    group2 = FactoryBot.create(
      :container_group,
      :name           => "group2",
      :container_node => node
    )
    FactoryBot.create(
      :container_image,
      :containers => [FactoryBot.create(:container, :name => "container_a", :container_group => group),
                      FactoryBot.create(:container, :name => "container_b", :container_group => group2)]
    )
    expect(FactoryBot.create(:container_project, :container_groups => [group]).container_images.count).to eq(1)
  end
end
