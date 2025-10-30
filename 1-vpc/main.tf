provider "aws" {
  region = "ap-northeast-2"
}

resource "aws_vpc" "gj_lab_vpc" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name    = "gj-lab-vpc"
    Project = "gj-lab"
  }
}

resource "aws_internet_gateway" "gj_lab_igw" {
  vpc_id = aws_vpc.gj_lab_vpc.id
  tags = {
    Name = "gj-lab-igw"
  }
}

resource "aws_subnet" "public_2a" {
  vpc_id                  = aws_vpc.gj_lab_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "ap-northeast-2a"
  map_public_ip_on_launch = true
  tags = {
    Name = "gj-lab-public-2a"
  }
}

resource "aws_subnet" "public_2c" {
  vpc_id                  = aws_vpc.gj_lab_vpc.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "ap-northeast-2c"
  map_public_ip_on_launch = true
  tags = {
    Name = "gj-lab-public-2c"
  }
}

resource "aws_subnet" "private_2a" {
  vpc_id            = aws_vpc.gj_lab_vpc.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "ap-northeast-2a"
  tags = {
    Name = "gj-lab-private-2a"
  }
}

resource "aws_subnet" "private_2c" {
  vpc_id            = aws_vpc.gj_lab_vpc.id
  cidr_block        = "10.0.4.0/24"
  availability_zone = "ap-northeast-2c"
  tags = {
    Name = "gj-lab-private-2c"
  }
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.gj_lab_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.gj_lab_igw.id
  }
  tags = {
    Name = "gj-lab-public-rt"
  }
}

resource "aws_route_table_association" "public_2a_assoc" {
  subnet_id      = aws_subnet.public_2a.id
  route_table_id = aws_route_table.public_rt.id
}

resource "aws_route_table_association" "public_2c_assoc" {
  subnet_id      = aws_subnet.public_2c.id
  route_table_id = aws_route_table.public_rt.id
}