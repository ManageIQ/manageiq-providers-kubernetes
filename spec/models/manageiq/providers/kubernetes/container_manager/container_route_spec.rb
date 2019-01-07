describe ContainerRoute do
  it "has distinct nodes" do
    node = FactoryBot.create(:container_node, :name => "n")
    expect(FactoryBot.create(
      :container_route,
      :name => "rt",
      :container_service => FactoryBot.create(
        :container_service,
        :name => "s",
        :container_groups => [FactoryBot.create(:container_group, :name => "g1", :container_node => node),
                              FactoryBot.create(:container_group, :name => "g2", :container_node => node)]
      )
    ).container_nodes.count).to eq(1)
  end
end
