resource "aws_eks_cluster" "main" {
  name     = "my-cluster"
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids = [
      aws_subnet.private_subnet_eks_1a.id,
      aws_subnet.private_subnet_eks_1b.id
    ]

    security_group_ids      = [aws_security_group.eks_sg.id]
    endpoint_private_access = true
    endpoint_public_access  = true
  }

  depends_on = [
    aws_iam_role_policy_attachment.eks_cluster_policy
  ]
}


resource "aws_eks_node_group" "main_nodes" {
  cluster_name    = aws_eks_cluster.main.name
  node_group_name = "my-node-group"
  node_role_arn   = aws_iam_role.eks_node_role.arn

  subnet_ids = [
    aws_subnet.private_subnet_eks_1a.id,
    aws_subnet.private_subnet_eks_1b.id
  ]

  instance_types = ["t3.small"]
  capacity_type  = "SPOT"

  scaling_config {
    desired_size = 3
    min_size     = 3
    max_size     = 4
  }

  depends_on = [
    aws_iam_role_policy_attachment.node_policy_1,
    aws_iam_role_policy_attachment.node_policy_2,
    aws_iam_role_policy_attachment.node_policy_3
  ]
}

