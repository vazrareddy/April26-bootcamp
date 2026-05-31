#  vpc
resource "aws_vpc" "main" {
  cidr_block = var.vpc_cidr
  region = var.aws_region
  enable_dns_hostnames = var.enable_dns_hostnames
  enable_dns_support = var.enable_dns_support

  tags = {
    Name = var.vpc_name
  }
}

# ─── Public Subnets ───────────────────────────────────────────────────────────

resource "aws_subnet" "public" {
  count = length(var.public_subnet_data)
  region = var.aws_region
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_data[count.index].cidr
  map_public_ip_on_launch = true
  availability_zone       = var.public_subnet_data[count.index].availability_zone

  tags = {
    Name = "${var.vpc_name}-${var.public_subnet_data[count.index].prefix}-${count.index + 1}"
  }
}

# internet gateway
resource "aws_internet_gateway" "gw" {
  region = var.aws_region
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-igw"
  }
}

# public route table
resource "aws_route_table" "public" {
  region = var.aws_region
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gw.id
  }

  tags = {
    Name = "${var.vpc_name}-public-rt"
  }
}

# associate public subnets with public route table
resource "aws_route_table_association" "public" {
  region = var.aws_region
  count          = length(var.public_subnet_data)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}


#####################################

resource "aws_subnet" "private" {
  count = length(var.private_subnet_data)
  region = var.aws_region

  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.private_subnet_data[count.index].cidr
  map_public_ip_on_launch = false
  availability_zone       = var.private_subnet_data[count.index].availability_zone

  tags = {
    Name = "${var.vpc_name}-${var.private_subnet_data[count.index].prefix}-${count.index + 1}"
  }
}

# private route table
resource "aws_route_table" "private" {
  region = var.aws_region
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${var.vpc_name}-private-rt"
  }
}

#  subnet association with private route table
resource "aws_route_table_association" "private" {
  region = var.aws_region
  count          = length(var.private_subnet_data)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}


# elastic ip for nat gateway
resource "aws_eip" "nat" {
  ## count = var.need_nat_gateway && !var.need_single_nat_gateway ? length(var.public_subnet_data) : 1 ##
  # count = var.need_nat_gateway ? var.need_single_nat_gateway ? 1: 2 : 0
  count = var.need_nat_gateway ? var.need_single_nat_gateway ? 1 : length(var.public_subnet_data) : 0
}

# nat gateway
resource "aws_nat_gateway" "nat" {
 
  count         = var.need_nat_gateway ? var.need_single_nat_gateway ? 1 : length(var.public_subnet_data) : 0
  allocation_id = aws_eip.nat[count.index].id
  # Calculate the subnet index using modulo operator to cycle through available public subnets
  # This ensures even distribution of resources across multiple subnets when count exceeds subnet count
  subnet_id = aws_subnet.public[count.index % length(var.public_subnet_data)].id
   region = var.aws_region

  tags = {
    Name = "${var.vpc_name}-nat-${count.index + 1}"
  }
}

# route for the route table
resource "aws_route" "private" {
  count                  = var.need_nat_gateway ? var.need_single_nat_gateway ? 1 : length(var.public_subnet_data) : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat[count.index].id
  region = var.aws_region
}
