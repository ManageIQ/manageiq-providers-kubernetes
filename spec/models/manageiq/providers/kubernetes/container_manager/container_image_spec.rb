describe ContainerImage do
  it "has distinct nodes" do
    group = FactoryBot.create(
      :container_group,
      :name => "group",
      :container_node => FactoryBot.create(:container_node, :name => "node")
    )
    expect(FactoryBot.create(
      :container_image,
      :containers => [FactoryBot.create(:container, :name => "container_a", :container_group => group),
                      FactoryBot.create(:container, :name => "container_b", :container_group => group)]
    ).container_nodes.count).to eq(1)
    end
end

