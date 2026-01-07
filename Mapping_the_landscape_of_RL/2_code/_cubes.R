
rotate_points = function(points, angle_x = 0, angle_y = 0, angle_z = 0) {
  ax = angle_x * pi / 180
  ay = angle_y * pi / 180
  az = angle_z * pi / 180
  
  Rx = matrix(c(
    1, 0, 0,
    0, cos(ax), -sin(ax),
    0, sin(ax), cos(ax)
  ), nrow = 3, byrow = TRUE)
  
  Ry = matrix(c(
    cos(ay), 0, sin(ay),
    0, 1, 0,
    -sin(ay), 0, cos(ay)
  ), nrow = 3, byrow = TRUE)
  
  Rz = matrix(c(
    cos(az), -sin(az), 0,
    sin(az), cos(az), 0,
    0, 0, 1
  ), nrow = 3, byrow = TRUE)
  
  R = Rz %*% Ry %*% Rx
  
  rotated_points = t(R %*% t(points))
  return(rotated_points)
}


perspective_project = function(x, y, z, d = 5) {
  factor = d / (d - z)
  xp = x * factor
  yp = y * factor
  return(cbind(xp, yp, z))
}


square = function(angles = c(0, 0, 0), d = 5, orig = c(0, 0, 0), size = 1, scale = FALSE){

  vertices = rbind(
    c(0, 0, 0),
    c(1, 0, 0),
    c(1, 1, 0),
    c(0, 1, 0),
    c(0, 0, 1),
    c(1, 0, 1),
    c(1, 1, 1),
    c(0, 1, 1))
  
  # vertices = rbind(
  #   c(-.5, -.5, -.5),
  #   c(.5, -.5, -.5),
  #   c(.5, .5, -.5),
  #   c(-.5, .5, -.5),
  #   c(-.5, -.5, .5),
  #   c(.5, -.5, .5),
  #   c(.5, .5, .5),
  #   c(-.5, .5, .5))
  
  vertices = vertices * size
  vertices = t(t(vertices) + orig)
    
  rownames(vertices) = c("A", "B", "C", "D", "E", "F", "G", "H")
    
  rotated_vertices = rotate_points(vertices, angle_x = angles[1], angle_y = angles[2], angle_z = angles[3])
  proj = perspective_project(rotated_vertices[,1], rotated_vertices[,2], rotated_vertices[,3], d = d)
  
  if(scale){
  x = proj["H",3]
  mx = 10.48
  mn = -6.43
  x = (x - mn) / (mx - mn)
  x = x / 3 + (2/3)
    for(i in 1:2){
      proj[,i] = mean(proj[,i]) + (proj[,i] - mean(proj[,i])) * x
    }
  }
  
  proj 
  }


line = function(points, angles = c(0, 0, 0), d = 5, orig = c(0, 0, 0), size = 1, scale = FALSE){
  
  rotated_vertices = rotate_points(points, angle_x = angles[1], angle_y = angles[2], angle_z = angles[3])
  proj = perspective_project(rotated_vertices[,1], rotated_vertices[,2], rotated_vertices[,3], d = d)
  proj
  }

segs = function(proj, faces = 1){
  
  vertices = rbind(
    c(0, 0, 0),
    c(1, 0, 0),
    c(1, 1, 0),
    c(0, 1, 0),
    c(0, 0, 1),
    c(1, 0, 1),
    c(1, 1, 1),
    c(0, 1, 1))
  
  rownames(vertices) = c("A", "B", "C", "D", "E", "F", "G", "H")
  
    if(faces == 1){
  
    edges = list(
      c("A", "B"), c("B", "C"), c("C", "D"), 
      c("D", "A"), c("E", "F"), c("F", "G"),  
      c("A", "E"), c("B", "F"), c("C", "G")
    )
  
    #text(proj[,1], proj[,2], labels = rownames(proj))
    
    for(edge in edges) {
      idx1 = which(rownames(vertices) == edge[1])
      idx2 = which(rownames(vertices) == edge[2])
      segments(proj[idx1, 1], proj[idx1, 2],
               proj[idx2, 1], proj[idx2, 2])
    }
  
    
    } else {
      edges = list(c("H", "E"), c("D", "H"),c("G", "H"))
      
      for(edge in edges) {
        idx1 = which(rownames(vertices) == edge[1])
        idx2 = which(rownames(vertices) == edge[2])
        segments(proj[idx1, 1], proj[idx1, 2],
                 proj[idx2, 1], proj[idx2, 2])
      }
    }
  }

fact = function(x, d) d / (d - x)

faces = function(proj, col = "black", border = "white", d = 50, lwd = .5){
  
  # x = proj["H",3]
  # mx = 10.48
  # mn = -6.43
  # x = (x - mn) / (mx - mn)
  # x = x / 10
  # 
  # #print(factor)
  # col = memnet::cmix(col, "white", .1-x)
  # border = memnet::cmix(border, "white", .1-x)
  
  polygon(proj[c("A","E","H","D"),1], proj[c("A","E","H","D"),2], col = col, border=border, lwd=lwd)
  polygon(proj[c("F","E","H","G"),1], proj[c("F","E","H","G"),2], col = col, border=border, lwd=lwd)
  polygon(proj[c("C","D","H","G"),1], proj[c("C","D","H","G"),2], col = col, border=border, lwd=lwd)
  
  #text(proj["H",1],proj["H",2],labels = round(proj["H",3],1), cex=.5)
  
}




draw = function(angles, d = 1000, size = 1, nudge_x = 0, nudge_y = 0, segment = TRUE){
  sq = square(angles, d = d, size = size, nudge_x = nudge_x, nudge_y = nudge_y) 
  if(segment) add_segments(sq) else add_faces(sq)
  }


# 
# 
# sq = square(35, 45, 26.5) 
# 
# angles = c(35, 45, 26.5)
# 
# 
# 
# draw(ang, size = 1, d = 5)
# draw(ang, size = .05, nudge_x = .3, nudge_y = .2, segment = FALSE, d = 5)
# 
# 


# abline(h = c(0, .99), col = "red")
# abline(v = .75, col = "red")
